//! Logs a failing metric once, not once per second.

/// Remembers whether a metric's failure has been logged since it last worked.
#[derive(Debug)]
pub struct LogOnce {
    metric: &'static str,
    failing: bool,
}

impl LogOnce {
    pub const fn new(metric: &'static str) -> Self {
        Self {
            metric,
            failing: false,
        }
    }

    /// Passes a value through. On error, logs the first failure in a row and
    /// returns `None`, so the caller reports the metric as zero or absent.
    pub fn check<T>(&mut self, result: anyhow::Result<T>) -> Option<T> {
        match result {
            Ok(value) => {
                if self.failing {
                    tracing::info!(metric = self.metric, "metric can be read again");
                    self.failing = false;
                }
                Some(value)
            }
            Err(error) => {
                if !self.failing {
                    tracing::warn!(
                        metric = self.metric,
                        error = format!("{error:#}"),
                        "could not read metric; reporting it as zero or absent until it recovers"
                    );
                    self.failing = true;
                }
                None
            }
        }
    }
}
