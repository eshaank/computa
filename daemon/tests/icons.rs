//! Starts the real daemon on a free port and asks it for the icons of
//! fixture bundles built in a temporary directory.

use std::io::Cursor;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use computad::pb::GetAppIconRequest;
use computad::pb::monitor_client::MonitorClient;
use computad::processes::ProcessMonitor;
use computad::rex::CliRex;
use computad::rpc;
use computad::sampler::Sampler;
use computad::sessions::SessionMonitor;
use icns::{IconFamily, IconType, Image, PixelFormat};
use tokio::net::TcpListener;
use tonic::transport::Channel;

const PNG_SIGNATURE: &[u8] = b"\x89PNG\r\n\x1a\n";

async fn start() -> (MonitorClient<Channel>, tokio::sync::oneshot::Sender<()>) {
    let sampler = Arc::new(Sampler::start().expect("sampler starts"));
    let processes = ProcessMonitor::darwin();
    let sessions = SessionMonitor::new(Arc::new(CliRex::from_env()), processes.clone());
    let listener = TcpListener::bind("127.0.0.1:0").await.expect("bind");
    let addr = listener.local_addr().expect("local addr");
    let (stop_tx, stop_rx) = tokio::sync::oneshot::channel::<()>();
    tokio::spawn(async move {
        let shutdown = async {
            let _ = stop_rx.await;
        };
        rpc::serve(listener, sampler, processes, sessions, shutdown)
            .await
            .expect("server runs");
    });
    let client = MonitorClient::connect(format!("http://{addr}"))
        .await
        .expect("connect");
    (client, stop_tx)
}

/// A temporary directory removed when dropped.
struct TempDir(PathBuf);

impl TempDir {
    fn new(tag: &str) -> Self {
        let dir = std::env::temp_dir().join(format!("computad-it-{tag}-{}", std::process::id()));
        std::fs::create_dir_all(&dir).expect("create temp dir");
        Self(dir)
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        if let Err(error) = std::fs::remove_dir_all(&self.0) {
            eprintln!("could not remove {}: {error}", self.0.display());
        }
    }
}

/// `<dir>/<name>.app` with an Info.plist naming `AppIcon` as its icon file,
/// and that icon only when `with_icon`.
fn bundle(dir: &Path, name: &str, with_icon: bool) -> String {
    let root = dir.join(format!("{name}.app"));
    let resources = root.join("Contents/Resources");
    std::fs::create_dir_all(&resources).expect("create bundle");
    let plist = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\"><dict>\
                 <key>CFBundleIconFile</key><string>AppIcon</string></dict></plist>\n";
    std::fs::write(root.join("Contents/Info.plist"), plist).expect("write plist");
    if with_icon {
        let mut image = Image::new(PixelFormat::RGBA, 512, 512);
        image.data_mut().fill(200);
        let mut family = IconFamily::new();
        family
            .add_icon_with_type(&image, IconType::RGBA32_512x512)
            .expect("encode icon");
        let file = std::fs::File::create(resources.join("AppIcon.icns")).expect("create icns");
        family.write(file).expect("write icns");
    }
    root.to_str().expect("utf8").to_owned()
}

async fn icon(client: &mut MonitorClient<Channel>, path: &str) -> Result<Vec<u8>, tonic::Status> {
    let request = GetAppIconRequest {
        bundle_path: path.to_owned(),
    };
    client
        .get_app_icon(request)
        .await
        .map(|r| r.into_inner().png)
}

#[tokio::test]
async fn get_app_icon_returns_a_small_png() {
    let dir = TempDir::new("with");
    let path = bundle(&dir.0, "WithIcon", true);
    let (mut client, stop) = start().await;

    let png = icon(&mut client, &path).await.expect("icon");
    assert!(png.starts_with(PNG_SIGNATURE), "not a PNG");
    let image = Image::read_png(Cursor::new(&png)).expect("decodes");
    assert_eq!((image.width(), image.height()), (128, 128));

    let again = icon(&mut client, &path).await.expect("cached icon");
    assert_eq!(again, png, "a second call returns the same bytes");
    let _ = stop.send(());
}

#[tokio::test]
async fn get_app_icon_returns_empty_without_an_icon() {
    let dir = TempDir::new("without");
    let path = bundle(&dir.0, "NoIcon", false);
    let (mut client, stop) = start().await;
    let png = icon(&mut client, &path).await.expect("not an error");
    assert!(png.is_empty(), "{} bytes", png.len());
    let _ = stop.send(());
}

#[tokio::test]
async fn get_app_icon_rejects_bad_paths() {
    let dir = TempDir::new("bad");
    let real = bundle(&dir.0, "Real", false);
    let (mut client, stop) = start().await;
    let bad = [
        "Real.app".to_owned(),
        dir.0.to_str().expect("utf8").to_owned(),
        format!("{real}/../Real.app"),
        dir.0.join("Missing.app").to_str().expect("utf8").to_owned(),
    ];
    for path in bad {
        let status = icon(&mut client, &path).await.expect_err("must fail");
        assert_eq!(
            status.code(),
            tonic::Code::InvalidArgument,
            "{path}: {status:?}"
        );
        assert!(!status.message().is_empty());
    }
    let _ = stop.send(());
}
