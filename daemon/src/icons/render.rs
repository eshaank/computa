//! Decodes an `.icns` file and turns one of its images into a small PNG.

use std::io::Cursor;

use anyhow::{Context, bail};
use icns::{IconFamily, IconType, Image, PixelFormat};

/// The largest side of a returned icon, in pixels.
pub const MAX_SIDE: u32 = 128;

/// Orders the available icon types by preference: the smallest that is at
/// least [`MAX_SIDE`] pixels wide first, then larger ones, then smaller ones
/// from the largest down. Later entries are fallbacks for ones that fail to
/// decode.
pub fn preference_order(types: &[IconType]) -> Vec<IconType> {
    let mut ordered = types.to_vec();
    ordered.sort_by_key(|t| {
        let width = t.pixel_width();
        let rank = if width >= MAX_SIDE {
            u64::from(width)
        } else {
            u64::from(u32::MAX) + u64::from(MAX_SIDE - width)
        };
        (rank, t.pixel_density())
    });
    ordered
}

/// The size an image of `width` × `height` is scaled to: unchanged when it
/// fits in [`MAX_SIDE`], otherwise shrunk to fit, keeping the aspect ratio.
pub fn fit(width: u32, height: u32) -> (u32, u32) {
    let longest = width.max(height);
    if longest <= MAX_SIDE {
        return (width, height);
    }
    let scale = |side: u32| {
        let scaled =
            (u64::from(side) * u64::from(MAX_SIDE) + u64::from(longest) / 2) / u64::from(longest);
        u32::try_from(scaled.max(1)).unwrap_or(MAX_SIDE)
    };
    (scale(width), scale(height))
}

/// Shrinks RGBA pixels to `to` with a box filter. Colours are weighted by
/// alpha so transparent pixels do not darken the edges.
pub fn downscale(rgba: &[u8], from: (u32, u32), to: (u32, u32)) -> Vec<u8> {
    let (sw, sh) = (from.0 as usize, from.1 as usize);
    let (dw, dh) = (to.0 as usize, to.1 as usize);
    let mut out = Vec::with_capacity(dw * dh * 4);
    for oy in 0..dh {
        let (y0, y1) = span(oy, sh, dh);
        for ox in 0..dw {
            let (x0, x1) = span(ox, sw, dw);
            out.extend_from_slice(&average(rgba, sw, (x0, x1), (y0, y1)));
        }
    }
    out
}

/// The source range covered by destination index `i`.
fn span(i: usize, source: usize, dest: usize) -> (usize, usize) {
    let start = i * source / dest;
    let end = ((i + 1) * source / dest).max(start + 1).min(source);
    (start, end)
}

fn average(rgba: &[u8], stride: usize, xs: (usize, usize), ys: (usize, usize)) -> [u8; 4] {
    let mut sums = [0u64; 4];
    let mut count = 0u64;
    for y in ys.0..ys.1 {
        for x in xs.0..xs.1 {
            let p = &rgba[(y * stride + x) * 4..][..4];
            let alpha = u64::from(p[3]);
            for c in 0..3 {
                sums[c] += u64::from(p[c]) * alpha;
            }
            sums[3] += alpha;
            count += 1;
        }
    }
    let channel = |sum: u64, by: u64| u8::try_from((sum + by / 2) / by.max(1)).unwrap_or(255);
    let alpha_sum = sums[3];
    [
        channel(sums[0], alpha_sum),
        channel(sums[1], alpha_sum),
        channel(sums[2], alpha_sum),
        channel(alpha_sum, count),
    ]
}

/// Decodes the best image in an `.icns` file and returns it as a PNG of at
/// most [`MAX_SIDE`] pixels on a side.
pub fn icns_to_png(bytes: &[u8]) -> anyhow::Result<Vec<u8>> {
    let family = IconFamily::read(Cursor::new(bytes)).context("cannot parse the .icns file")?;
    let image = decode_best(&family)?.convert_to(PixelFormat::RGBA);
    let from = (image.width(), image.height());
    let to = fit(from.0, from.1);
    let pixels = if to == from {
        image.into_data().into_vec()
    } else {
        downscale(image.data(), from, to)
    };
    let small = Image::from_data(PixelFormat::RGBA, to.0, to.1, pixels)
        .context("cannot build the scaled image")?;
    let mut png = Vec::new();
    small.write_png(&mut png).context("cannot encode the PNG")?;
    Ok(png)
}

fn decode_best(family: &IconFamily) -> anyhow::Result<Image> {
    for icon_type in preference_order(&family.available_icons()) {
        match family.get_icon_with_type(icon_type) {
            Ok(image) if image.width() > 0 && image.height() > 0 => return Ok(image),
            Ok(_) => tracing::debug!(?icon_type, "skipping an empty icon element"),
            Err(error) => {
                tracing::debug!(?icon_type, %error, "cannot decode an icon element; trying the next")
            }
        }
    }
    bail!("the .icns file has no image this daemon can decode")
}

#[cfg(test)]
#[path = "render_tests.rs"]
mod tests;
