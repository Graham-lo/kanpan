package p398sh.aicoin.kline.tools;

import app.aicoin.base.kline.R;
import com.umeng.commonsdk.statistics.SdkVersion;

/* JADX INFO: loaded from: classes7.dex */
public final class a {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public static final a f140672a = new a();

    /* JADX WARN: Failed to restore switch over string. Please report as a decompilation issue */
    public final int a(String str) {
        switch (str.hashCode()) {
            case 49:
                if (str.equals(SdkVersion.MINI_VERSION)) {
                    return R.string.kline_menu_time_1m;
                }
                break;
            case 51:
                if (str.equals("3")) {
                    return R.string.kline_menu_time_3m;
                }
                break;
            case 53:
                if (str.equals("5")) {
                    return R.string.kline_menu_time_5m;
                }
                break;
            case 1567:
                if (str.equals("10")) {
                    return R.string.kline_menu_time_10m;
                }
                break;
            case 1572:
                if (str.equals("15")) {
                    return R.string.kline_menu_time_15m;
                }
                break;
            case 1629:
                if (str.equals("30")) {
                    return R.string.kline_menu_time_30m;
                }
                break;
            case 1722:
                if (str.equals("60")) {
                    return R.string.kline_menu_time_1h;
                }
                break;
            case 48687:
                if (str.equals("120")) {
                    return R.string.kline_menu_time_2h;
                }
                break;
            case 48873:
                if (str.equals("180")) {
                    return R.string.kline_menu_time_3h;
                }
                break;
            case 49710:
                if (str.equals("240")) {
                    return R.string.kline_menu_time_4h;
                }
                break;
            case 50733:
                if (str.equals("360")) {
                    return R.string.kline_menu_time_6h;
                }
                break;
            case 54453:
                if (str.equals("720")) {
                    return R.string.kline_menu_time_12h;
                }
                break;
            case 1511391:
                if (str.equals("1440")) {
                    return R.string.kline_menu_time_1d;
                }
                break;
            case 1545150:
                if (str.equals("2880")) {
                    return R.string.kline_menu_time_2d;
                }
                break;
            case 1599741:
                if (str.equals("4320")) {
                    return R.string.kline_menu_time_3d;
                }
                break;
            case 1688091:
                if (str.equals("7200")) {
                    return R.string.kline_menu_time_5d;
                }
                break;
            case 46730409:
                if (str.equals("10080")) {
                    return R.string.kline_menu_time_1w;
                }
                break;
            case 49592019:
                if (str.equals("43200")) {
                    return R.string.kline_menu_time_1mn;
                }
                break;
            case 1450755966:
                if (str.equals("129600")) {
                    return R.string.kline_menu_time_1q;
                }
                break;
            case 1564317336:
                if (str.equals("518400")) {
                    return R.string.kline_menu_time_year;
                }
                break;
        }
        return R.string.sh_base_value_unset;
    }
}
