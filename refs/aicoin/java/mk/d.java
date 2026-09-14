package mk;

import android.graphics.Color;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class d extends b {

    /* JADX INFO: renamed from: j, reason: collision with root package name */
    public final int f133618j = d(".main_green.color");

    /* JADX INFO: renamed from: k, reason: collision with root package name */
    public final int f133619k = d(".main_red.color");

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final int f133620l = d(".main_candle_green.color");

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final int f133621m = d(".main_candle_red.color");

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final int f133622n = -3402732;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final int f133623o = -16777216;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public final int f133624p = -5592406;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public final int f133625q = -5395027;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public final int f133626r = Color.parseColor("#FFF7F8FA");

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public final int f133627s = Color.parseColor("#FFF2F4F7");

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public final int f133628t = Color.parseColor("#FF59677B");

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public final int f133629u = -68365;

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public final int f133630v = -787723;

    /* JADX INFO: renamed from: w, reason: collision with root package name */
    public final int f133631w = -8246398;

    /* JADX INFO: renamed from: x, reason: collision with root package name */
    public final int f133632x = -835781;

    /* JADX INFO: renamed from: y, reason: collision with root package name */
    public final int f133633y = -11685377;

    /* JADX INFO: renamed from: z, reason: collision with root package name */
    public final int f133634z = -853505;

    /* JADX INFO: renamed from: A, reason: collision with root package name */
    public final int f133617A = -11489061;

    @Override // mk.b
    public int A() {
        return this.f133618j;
    }

    @Override // mk.b
    public int B() {
        return this.f133619k;
    }

    @Override // mk.b
    public void C() {
        a(".price_info.bg", 0);
        a(".price_info.land.bg", 0);
        a(".price_info.text_timestamp", -5393453);
        a(".price_info.text_title", -8617310);
        a(".price_info.text_value", -8617310);
        a(".price_info.unit_value", -6710887);
        a(".strategy.middle", -22016);
        a(".growth_info.positive", -11621776);
        a(".growth_info.negative", -35217);
        a(".order_point.circle.red", -709331);
        a(".order_point.circle.green", -12076222);
        a(".order_point.text_color", -1);
        a(".order_point.shadow_color", -2142022829);
        a(".drawing.line", -13154481);
        a(".drawing.text", -13154481);
        a(".drawing.bg", -1276186898);
        a(".rangeTint.content", 552094137);
        a(".rangeTint.border", 1441286585);
        a(".fund_flow.center", -19456);
        a(".main_red.color", -1686190);
        a(".main_green.color", -13192617);
        a(".main_candle_red.color", x().getInt("light-.main_candle_red.color", -1686190));
        a(".main_candle_green.color", x().getInt("light-.main_candle_green.color", -13192617));
        a("indicator_line_color_0", -13643086);
        a("indicator_line_color_1", -19456);
        a("indicator_line_color_2", -1553991);
        a("indicator_line_color_3", -15435576);
        a("indicator_line_color_4", -5054582);
        a("indicator_line_color_5", -288103);
        a("indicator_line_color_6", -16726565);
        a("indicator_line_color_7", -683264);
        a("indicator_line_color_8", -7334914);
        a("indicator_line_color_9", -8355712);
        a(".background_plot.color", -1);
        a(".background_selection_tick.color", -1);
        a(".background_price_tag.color", -8746855);
        a(".background_volume_price_tag.color", -264206);
        a(".background_last_price_tag.color", -723724);
        a(".frame_price_tag.color", -3351041);
        a(".volume.latest_color", -1663696);
        a("value_indicator_line_color_0", -5592406);
        a("value_indicator_line_color_1", -5592406);
        a("value_indicator_line_color_2", -5592406);
        a(".background_alert_tg.color", -15435526);
        a(".background_alert_line_price_pop_tg.color", -1);
        a(".background_alert_line_price_text_tg.color", Color.parseColor("#333333"));
    }

    @Override // mk.a
    public int b(int i10) {
        return d("indicator_line_color_" + i10);
    }

    @Override // mk.a
    public int c(int i10) {
        switch (i10) {
            case 1:
                return d(".background_plot.color");
            case 2:
                return d(".background_selection_tick.color");
            case 3:
                return d(".background_price_tag.color");
            case 4:
                return d(".frame_price_tag.color");
            case 5:
                return d(".background_last_price_tag.color");
            case 6:
                return d(".background_volume_price_tag.color");
            case 7:
                return d(".background_alert_tg.color");
            case 8:
                return -723724;
            case 9:
                return d(".background_alert_line_price_pop_tg.color");
            case 10:
                return d(".background_alert_line_price_text_tg.color");
            default:
                return -1;
        }
    }

    @Override // mk.a
    public int e() {
        return this.f133633y;
    }

    @Override // mk.a
    public int f() {
        return this.f133634z;
    }

    @Override // mk.b, mk.a
    public int g(int i10) {
        if (i10 == 1) {
            return -1182468;
        }
        if (i10 == 2 || i10 == 4) {
            return -1381654;
        }
        if (i10 == 5) {
            return 0;
        }
        if (i10 != 6) {
            return super.g(i10);
        }
        return -1381654;
    }

    @Override // mk.a
    public int h() {
        return this.f133625q;
    }

    @Override // mk.a
    public int i() {
        return this.f133628t;
    }

    @Override // mk.a
    public int j() {
        return this.f133627s;
    }

    @Override // mk.a
    public int k() {
        return KLineManager.f142490O.a().V() ? this.f133630v : this.f133629u;
    }

    @Override // mk.a
    public int n(int i10) {
        if (i10 == 0) {
            return -16619085;
        }
        if (i10 != 1) {
            return i10 != 2 ? 0 : -14969280;
        }
        return -486106;
    }

    @Override // mk.a
    public int o() {
        return this.f133617A;
    }

    @Override // mk.a
    public int p() {
        return KLineManager.f142490O.a().V() ? this.f133629u : this.f133630v;
    }

    @Override // mk.a
    public int s() {
        return this.f133626r;
    }

    @Override // mk.a
    public int t() {
        return this.f133624p;
    }

    @Override // mk.b, mk.a
    public int u(int i10) {
        switch (i10) {
            case 1:
            case 2:
            case 3:
                return -5592406;
            case 4:
                return -7829368;
            case 5:
                return -6908266;
            case 6:
                return -1;
            case 7:
            default:
                return super.u(i10);
            case 8:
                return -65536;
            case 9:
                return -16776961;
            case 10:
                return -11877718;
            case 11:
                return -233297;
            case 12:
                return -9657359;
            case 13:
            case 14:
                return -1;
            case 15:
                return -5592406;
        }
    }

    @Override // mk.a
    public boolean w() {
        return false;
    }

    @Override // mk.b
    public int y() {
        return this.f133620l;
    }

    @Override // mk.b
    public int z() {
        return this.f133621m;
    }
}
