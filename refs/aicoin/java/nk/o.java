package nk;

import java.util.List;
import java.util.Locale;
import org.apache.tika.metadata.DublinCore;
import org.apache.tika.mime.MimeTypesReaderMetKeys;

/* JADX INFO: loaded from: classes7.dex */
public final class o {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public static final o f134231a = new o();

    public static final String c(int i10) {
        switch (i10) {
            case 1:
                return "macd";
            case 2:
                return "kdj";
            case 3:
                return "rsi";
            case 4:
                return "stochrsi";
            case 5:
                return "obv";
            case 6:
                return "trix";
            case 7:
                return "wr";
            case 8:
                return "cci";
            case 9:
                return "roc";
            case 10:
                return "atr";
            case 11:
                return "volume";
            case 12:
                return "fundflow";
            case 13:
                return "dmi";
            case 14:
                return "vr";
            case 15:
                return "psy";
            case 16:
                return "bias";
            case 17:
                return "smi";
            case 18:
                return "skdj";
            case 19:
                return "dma";
            case 20:
                return "mtm";
            case 21:
                return "bbw";
            case 22:
                return "position";
            case 23:
                return "ttsi";
            case 24:
                return "ttmu";
            case 25:
                return "brar";
            case 26:
                return "emv";
            case 27:
                return "mfi";
            case 28:
                return "boll";
            case 29:
                return "dpo";
            case 30:
                return "ao";
            case 31:
                return "lsur";
            case 32:
                return "basis";
            case 33:
                return "tvolume";
            case 34:
                return "ftbs";
            case 35:
                return "mlr";
            case 36:
                return "bsv";
            case 37:
                return "ai-fdi";
            case 38:
                return "ai-pd";
            case 39:
                return "ai-li";
            case 40:
                return "ai-bsi";
            case 41:
                return "ai-netvol";
            case 42:
                return "ai-bst";
            case 43:
                return "fr";
            case 44:
                return "pfr";
            case 45:
                return "sub_script_indicator";
            case 46:
                return "publicScript-cvd";
            case 47:
                return "publicScript-cvdCandle";
            case 48:
                return "publicScript-mc";
            case 49:
                return "publicScript-positionMc";
            case 50:
                return "publicScript-basisOkex";
            case 51:
                return "publicScript-basisBinance";
            case 52:
                return "publicScript-fundingRate";
            case 53:
                return "publicScript-coinContract";
            case 54:
                return "publicScript-usdtContract";
            case 55:
                return "publicScript-activeTradeValue";
            case 56:
                return "publicScript-activeTradeVolume";
            case 57:
                return "publicScript-activeTradeCount";
            default:
                return "";
        }
    }

    public static final String d(int i10) {
        switch (i10) {
            case 1:
                return "ma";
            case 2:
                return "ema";
            case 3:
                return "boll";
            case 4:
                return "sar";
            case 5:
                return "ene";
            case 6:
                return DublinCore.PREFIX_DC;
            case 7:
                return "alligator";
            case 8:
                return "ichimoku";
            case 9:
                return "kc";
            case 10:
                return "td";
            case 11:
                return "bbi";
            case 12:
                return "ai_srl";
            case 13:
                return "ai_large_order";
            case 14:
                return "ai_win_rate";
            case 15:
                return "ai_large_trade";
            case 16:
                return "vpvr";
            case 17:
                return "ai_handle_line";
            case 18:
                return "main_script_indicator";
            case 19:
                return "main_alert_line";
            case 20:
                return "main_liqui_line";
            case 21:
                return "liqheatmap";
            default:
                return "";
        }
    }

    /* JADX WARN: Failed to restore switch over string. Please report as a decompilation issue */
    public final String a(String str) {
        switch (str.hashCode()) {
            case -942198617:
                if (str.equals("ichimoku")) {
                    return "Ichimoku";
                }
                break;
            case -939671410:
                if (str.equals("tvolume")) {
                    return "TVolume";
                }
                break;
            case -387915688:
                if (str.equals("liqheatmap")) {
                    return "Heat Liquidation";
                }
                break;
            case 185869397:
                if (str.equals("alligator")) {
                    return "Alligator";
                }
                break;
            case 747804969:
                if (str.equals("position")) {
                    return "Position";
                }
                break;
            case 1381448051:
                if (str.equals("fundflow")) {
                    return "Fund flow";
                }
                break;
            case 1703413333:
                if (str.equals("stochrsi")) {
                    return "StochRSI";
                }
                break;
        }
        return str.toUpperCase(Locale.getDefault());
    }

    /* JADX WARN: Failed to restore switch over string. Please report as a decompilation issue */
    public final List b(String str) {
        switch (str.hashCode()) {
            case -939671410:
                if (str.equals("tvolume")) {
                    return Sf.r.q("time", "volume");
                }
                break;
            case -387915688:
                if (str.equals("liqheatmap")) {
                    return Sf.r.q("timestamp", "leverage", "direction", "fromPrice", "toPrice", "turnover");
                }
                break;
            case 3276:
                if (str.equals("fr")) {
                    return Sf.r.q("time", "fundingRate", "estimatedRate");
                }
                break;
            case 97861:
                if (str.equals("bsv")) {
                    return Sf.r.q("time", "buyVolume", "sellVolume");
                }
                break;
            case 108211:
                if (str.equals("mlr")) {
                    return Sf.r.q("time", "ratios");
                }
                break;
            case 2994085:
                if (str.equals("aili")) {
                    return Sf.r.q("timestamp", "buySize", "sellSize");
                }
                break;
            case 3153311:
                if (str.equals("ftbs")) {
                    return Sf.r.q("time", "buyVolume", "sellVolume");
                }
                break;
            case 3331684:
                if (str.equals("lsur")) {
                    return Sf.r.q("time", "ratios");
                }
                break;
            case 3570728:
                if (str.equals("ttmu")) {
                    return Sf.r.q("time", "buyInterest", "sellInterest");
                }
                break;
            case 3570902:
                if (str.equals("ttsi")) {
                    return Sf.r.q("time", "buyAccount");
                }
                break;
            case 92807451:
                if (str.equals("aibst")) {
                    return Sf.r.q("timestamp", "buyCount", "sellCount");
                }
                break;
            case 93508670:
                if (str.equals("basis")) {
                    return Sf.r.q("time", "basis");
                }
                break;
            case 135018193:
                if (str.equals("turnover")) {
                    return Sf.r.q("timestamp", "buyTurnover", "sellTurnover");
                }
                break;
            case 747804969:
                if (str.equals("position")) {
                    return Sf.r.q("time", "close");
                }
                break;
            case 1381448051:
                if (str.equals("fundflow")) {
                    return Sf.r.q("timestamp", MimeTypesReaderMetKeys.MATCH_VALUE_ATTR);
                }
                break;
        }
        return Sf.r.n();
    }
}
