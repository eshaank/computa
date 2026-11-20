use super::*;
use crate::icons::fixture::{self, TempDir};

fn widths(types: &[IconType]) -> Vec<u32> {
    preference_order(types)
        .iter()
        .map(|t| t.pixel_width())
        .collect()
}

#[test]
fn prefers_the_smallest_size_of_at_least_128() {
    let types = [
        IconType::RGBA32_512x512,
        IconType::RGBA32_16x16,
        IconType::RGBA32_256x256,
        IconType::RGBA32_128x128,
        IconType::RGBA32_32x32,
    ];
    assert_eq!(widths(&types), vec![128, 256, 512, 32, 16]);
}

#[test]
fn falls_back_to_the_largest_when_all_are_small() {
    let types = [
        IconType::RGBA32_16x16,
        IconType::RGBA32_64x64,
        IconType::RGBA32_32x32,
    ];
    assert_eq!(widths(&types)[0], 64);
}

#[test]
fn counts_retina_elements_by_pixel_size() {
    // 128x128@2x is 256 pixels wide, so the plain 256 one ties with it and
    // the 1x density wins the tie.
    let types = [IconType::RGBA32_128x128_2x, IconType::RGBA32_256x256];
    assert_eq!(preference_order(&types)[0], IconType::RGBA32_256x256);
}

#[test]
fn fit_keeps_aspect_ratio_and_never_exceeds_128() {
    assert_eq!(fit(1024, 1024), (128, 128));
    assert_eq!(fit(512, 256), (128, 64));
    assert_eq!(fit(100, 400), (32, 128));
    assert_eq!(fit(64, 32), (64, 32), "small images are not enlarged");
    assert_eq!(fit(5000, 1), (128, 1), "a side never rounds to zero");
    for (w, h) in [(129, 7), (333, 1000), (128, 129)] {
        let (a, b) = fit(w, h);
        assert!(a <= MAX_SIDE && b <= MAX_SIDE && a.max(b) == MAX_SIDE);
    }
}

#[test]
fn downscale_averages_and_weights_by_alpha() {
    // A 2x2 block: opaque red, transparent green, and two transparent pixels.
    let pixels = [255, 0, 0, 255, 0, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    let out = downscale(&pixels, (2, 2), (1, 1));
    assert_eq!(
        out,
        vec![255, 0, 0, 64],
        "colour from the opaque pixel only"
    );
}

#[test]
fn downscale_produces_the_target_size() {
    let src = fixture::image(300);
    let out = downscale(src.data(), (300, 300), (128, 128));
    assert_eq!(out.len(), 128 * 128 * 4);
    assert_eq!(&out[..4], &[255, 0, 0, 255], "left edge stays red");
    assert_eq!(
        &out[out.len() - 4..],
        &[0, 0, 255, 255],
        "right edge stays blue"
    );
}

fn png_size(png: &[u8]) -> (u32, u32) {
    let image = Image::read_png(Cursor::new(png)).expect("valid png");
    (image.width(), image.height())
}

#[test]
fn icns_to_png_scales_a_large_icon_down() {
    let dir = TempDir::new();
    let path = dir.path().join("Big.icns");
    fixture::write_icns(&path, &[IconType::RGBA32_512x512, IconType::RGBA32_32x32]);
    let png = icns_to_png(&std::fs::read(&path).expect("read")).expect("render");
    assert!(png.starts_with(b"\x89PNG\r\n\x1a\n"));
    assert_eq!(png_size(&png), (128, 128));
}

#[test]
fn icns_to_png_keeps_a_small_icon_as_is() {
    let dir = TempDir::new();
    let path = dir.path().join("Small.icns");
    fixture::write_icns(&path, &[IconType::RGBA32_32x32, IconType::RGBA32_16x16]);
    let png = icns_to_png(&std::fs::read(&path).expect("read")).expect("render");
    assert_eq!(png_size(&png), (32, 32));
}

#[test]
fn icns_to_png_rejects_garbage() {
    assert!(icns_to_png(b"definitely not an icns file").is_err());
}
