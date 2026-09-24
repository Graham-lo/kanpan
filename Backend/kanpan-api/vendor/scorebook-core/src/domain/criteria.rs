//! K 线行（`Bar`）与价格字符串校验。
//!
//! 记分簿网页版这里还有一整套 Decimal 判决（Criteria / evaluate / 聚合 / ATR），看盘的
//! 复盘判决走 `domain::native_review`，那一套在 vendor 时裁掉了，连带 bigdecimal 依赖；
//! 行情适配器只剩「这串是不是合法十进制」这一个校验，由下面的 `dec` 手写完成。
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Bar {
    pub start: DateTime<Utc>,
    pub end: DateTime<Utc>,
    pub open: String,
    pub high: String,
    pub low: String,
    pub close: String,
    /// 成交量，与价格一样是 Decimal 字符串。缓存里的旧行和不带量的来源为 null，
    /// 判决从不读它，只有重温舞台的 VOL 副图画它。
    #[serde(default)]
    pub volume: Option<String>,
}
/// 交易所回来的价格 / 数量字符串是否是合法十进制：`[+-]?数字[.数字][e[+-]数字]`，
/// 至少一位数字。错误码与裁剪前的 BigDecimal 版一致：超长 `decimal_too_long`、
/// 格式不对 `invalid_decimal`、小数位与指数折算后的标度超过 ±64 `decimal_exponent_out_of_range`。
pub fn dec(s: &str) -> Result<(), String> {
    if s.len() > 96 {
        return Err("decimal_too_long".into());
    }
    let invalid = || String::from("invalid_decimal");
    let body = s.strip_prefix(['+', '-']).unwrap_or(s);
    let (mantissa, exponent) = match body.find(['e', 'E']) {
        Some(i) => (&body[..i], Some(&body[i + 1..])),
        None => (body, None),
    };
    let (int, frac) = mantissa.split_once('.').unwrap_or((mantissa, ""));
    let digits = |p: &str| p.bytes().all(|c| c.is_ascii_digit());
    if int.len() + frac.len() == 0 || !digits(int) || !digits(frac) {
        return Err(invalid());
    }
    let exp: i64 = match exponent {
        None => 0,
        Some(e) => {
            let unsigned = e.strip_prefix(['+', '-']).unwrap_or(e);
            if unsigned.is_empty() || !digits(unsigned) {
                return Err(invalid());
            }
            e.parse().map_err(|_| invalid())?
        }
    };
    if (frac.len() as i64 - exp).abs() > 64 {
        return Err("decimal_exponent_out_of_range".into());
    }
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::dec;
    #[test]
    fn provider_prices_are_plain_decimals() {
        for ok in [
            "67432.10",
            "0.00001234",
            "1",
            "+1.5",
            "-0.1",
            "1.",
            ".5",
            "1e-8",
            "2.5E+3",
        ] {
            assert!(dec(ok).is_ok(), "{ok}");
        }
        for bad in [
            "", ".", "-", "1.2.3", "abc", "1e", "1e+", "0x10", " 1", "1_000", "NaN",
        ] {
            assert_eq!(dec(bad).unwrap_err(), "invalid_decimal", "{bad}");
        }
        assert_eq!(dec(&"1".repeat(97)).unwrap_err(), "decimal_too_long");
        assert_eq!(dec("1e-65").unwrap_err(), "decimal_exponent_out_of_range");
        assert_eq!(dec("1e65").unwrap_err(), "decimal_exponent_out_of_range");
        assert!(dec("1e64").is_ok());
    }
}
