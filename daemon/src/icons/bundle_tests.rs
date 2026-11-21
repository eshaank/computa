use super::*;
use crate::icons::fixture::{self, TempDir};

fn rejected(raw: &str) -> String {
    match validate(raw) {
        Err(InvalidPath(message)) => message,
        Ok(bundle) => panic!("{raw:?} was accepted as {bundle:?}"),
    }
}

#[test]
fn validate_rejects_bad_paths() {
    let dir = TempDir::new();
    let file = dir.path().join("File.app");
    std::fs::write(&file, b"not a bundle").expect("write");
    let existing = fixture::bundle(dir.path(), "Real", &[]);

    assert!(rejected("Applications/Safari.app").contains("absolute"));
    assert!(rejected("/Applications/Safari").contains(".app"));
    assert!(rejected("/Applications/Safari.app.zip").contains(".app"));
    let dotdot = format!("{}/../Real.app", existing.display());
    assert!(rejected(&dotdot).contains(".."));
    let missing = dir.path().join("Missing.app");
    assert!(rejected(missing.to_str().expect("utf8")).contains("no such bundle"));
    assert!(rejected(file.to_str().expect("utf8")).contains("not a directory"));
}

#[test]
fn validate_accepts_a_bundle_and_resolves_it() {
    let dir = TempDir::new();
    let root = fixture::bundle(dir.path(), "Real", &[]);
    let bundle = validate(root.to_str().expect("utf8")).expect("valid");
    assert_eq!(
        bundle.root,
        std::fs::canonicalize(&root).expect("canonicalize")
    );
}

#[test]
fn icon_file_name_adds_icns_only_when_needed() {
    assert_eq!(icon_file_name("AppIcon").expect("ok"), "AppIcon.icns");
    assert_eq!(icon_file_name("AppIcon.icns").expect("ok"), "AppIcon.icns");
    assert_eq!(icon_file_name("Icon.png").expect("ok"), "Icon.png");
}

#[test]
fn icon_file_name_rejects_paths() {
    for bad in [
        "../../etc/passwd",
        "sub/AppIcon",
        "/AppIcon.icns",
        "..",
        ".",
        "",
    ] {
        assert!(icon_file_name(bad).is_err(), "{bad:?} was accepted");
    }
}

#[test]
fn find_icon_prefers_icon_file_then_icon_name() {
    let dir = TempDir::new();
    let root = fixture::bundle(
        dir.path(),
        "Both",
        &[
            ("CFBundleIconFile", "Missing"),
            ("CFBundleIconName", "Named"),
        ],
    );
    let named = root.join("Contents/Resources/Named.icns");
    std::fs::write(&named, b"x").expect("write");
    let bundle = validate(root.to_str().expect("utf8")).expect("valid");
    assert!(find_icon(&bundle).expect("found").ends_with("Named.icns"));

    std::fs::write(root.join("Contents/Resources/Missing.icns"), b"x").expect("write");
    assert!(find_icon(&bundle).expect("found").ends_with("Missing.icns"));
}

#[test]
fn find_icon_reads_a_binary_plist() {
    let dir = TempDir::new();
    let root = fixture::bundle(dir.path(), "Binary", &[]);
    let mut dict = plist::Dictionary::new();
    dict.insert("CFBundleIconFile".into(), plist::Value::from("Bin"));
    plist::Value::Dictionary(dict)
        .to_file_binary(root.join("Contents/Info.plist"))
        .expect("write binary plist");
    std::fs::write(root.join("Contents/Resources/Bin.icns"), b"x").expect("write");
    let bundle = validate(root.to_str().expect("utf8")).expect("valid");
    assert!(find_icon(&bundle).expect("found").ends_with("Bin.icns"));
}

#[test]
fn find_icon_refuses_a_name_with_a_slash_and_symlinks_out() {
    let dir = TempDir::new();
    let root = fixture::bundle(dir.path(), "Escape", &[("CFBundleIconFile", "../../x")]);
    let bundle = validate(root.to_str().expect("utf8")).expect("valid");
    assert!(find_icon(&bundle).is_err());

    let outside = dir.path().join("outside.icns");
    std::fs::write(&outside, b"secret").expect("write");
    let link = root.join("Contents/Resources/Link.icns");
    std::os::unix::fs::symlink(&outside, &link).expect("symlink");
    let error = read_icon(&bundle, &link).expect_err("must refuse");
    assert!(
        format!("{error:#}").contains("outside the bundle"),
        "{error:#}"
    );
}

#[test]
fn read_icon_refuses_oversized_files() {
    let dir = TempDir::new();
    let root = fixture::bundle(dir.path(), "Big", &[]);
    let big = root.join("Contents/Resources/Big.icns");
    let file = std::fs::File::create(&big).expect("create");
    file.set_len(MAX_ICON_BYTES + 1).expect("grow");
    let bundle = validate(root.to_str().expect("utf8")).expect("valid");
    let error = read_icon(&bundle, &big).expect_err("must refuse");
    assert!(format!("{error:#}").contains("limit"), "{error:#}");
}
