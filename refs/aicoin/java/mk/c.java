package mk;

import android.graphics.Color;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class c extends b {

    /* JADX INFO: renamed from: j, reason: collision with root package name */
    public final boolean f133600j = true;

    /* JADX INFO: renamed from: k, reason: collision with root package name */
    public final int f133601k = d(".main_green.color");

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final int f133602l = d(".main_red.color");

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final int f133603m = d(".main_candle_green.color");

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final int f133604n = d(".main_candle_red.color");

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final int f133605o = -1;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public final int f133606p = -1;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public final int f133607q = -11908015;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public final int f133608r = -9539464;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public final int f133609s = Color.parseColor("#FF25282B");

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public final int f133610t = Color.parseColor("#FF1F2126");

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public final int f133611u = Color.parseColor("#FFC3C7D9");

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public final int f133612v = -14607848;

    /* JADX INFO: renamed from: w, reason: collision with root package name */
    public final int f133613w = -15196388;

    /* JADX INFO: renamed from: x, reason: collision with root package name */
    public final int f133614x = -14714700;

    /* JADX INFO: renamed from: y, reason: collision with root package name */
    public final int f133615y = -7655635;

    /* JADX INFO: renamed from: z, reason: collision with root package name */
    public final int f133616z = -16618023;

    /* JADX INFO: renamed from: A, reason: collision with root package name */
    public final int f133598A = -16049617;

    /* JADX INFO: renamed from: B, reason: collision with root package name */
    public final int f133599B = -12565683;

    @Override // mk.b
    public int A() {
        return this.f133601k;
    }

    @Override // mk.b
    public int B() {
        return this.f133602l;
    }

    @Override // mk.b
    public void C() {
        a(".price_info.bg", 0);
        a(".price_info.land.bg", 0);
        a(".price_info.text_timestamp", -9143931);
        a(".price_info.text_title", -9143931);
        a(".price_info.text_value", -7434590);
        a(".price_info.unit_value", -9538694);
        a(".strategy.middle", -22016);
        a(".growth_info.positive", -15222407);
        a(".growth_info.negative", -1212555);
        a(".order_point.circle.red", -709331);
        a(".order_point.circle.green", -12277696);
        a(".order_point.text_color", -1);
        a(".order_point.shadow_color", -2146627300);
        a(".drawing.line", -5194043);
        a(".drawing.text", -5194043);
        a(".drawing.bg", -1289344457);
        a(".rangeTint.content", 552993023);
        a(".rangeTint.border", 1442185471);
        a(".fund_flow.center", -397776);
        a(".main_red.color", -5033422);
        a(".main_green.color", -14906814);
        a(".main_candle_red.color", x().getInt("dark-.main_candle_red.color", -5033422));
        a(".main_candle_green.color", x().getInt("dark-.main_candle_green.color", -14906814));
        a("indicator_line_color_0", -2236963);
        a("indicator_line_color_1", -397776);
        a("indicator_line_color_2", -655105);
        a("indicator_line_color_3", -10044417);
        a("indicator_line_color_4", -5054582);
        a("indicator_line_color_5", -288103);
        a("indicator_line_color_6", -16738392);
        a("indicator_line_color_7", -3376640);
        a("indicator_line_color_8", -10079576);
        a("indicator_line_color_9", -11908534);
        a(".background_plot.color", -15920868);
        a(".background_selection_tick.color", -15723496);
        a(".background_price_tag.color", -10063488);
        a(".background_last_price_tag.color", -14934231);
        a(".background_volume_price_tag.color", -14541287);
        a(".frame_price_tag.color", -13684168);
        a(".volume.latest_color", -4883418);
        a("value_indicator_line_color_0", -11908015);
        a("value_indicator_line_color_1", -11908015);
        a("value_indicator_line_color_2", -11908015);
        a(".background_alert_tg.color", -15703864);
        a(".background_alert_line_price_pop_tg.color", Color.parseColor("#333333"));
        a(".background_alert_line_price_text_tg.color", Color.parseColor("#FFC3C7D9"));
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
                return -14934231;
            case 9:
                return d(".background_alert_line_price_pop_tg.color");
            case 10:
                return d(".background_alert_line_price_text_tg.color");
            default:
                return -16777216;
        }
    }

    @Override // mk.a
    public int e() {
        return this.f133616z;
    }

    @Override // mk.a
    public int f() {
        return this.f133598A;
    }

    @Override // mk.b, mk.a
    public int g(int i10) {
        if (i10 == 1) {
            return -14342098;
        }
        if (i10 == 2 || i10 == 4) {
            return -13947075;
        }
        if (i10 == 5) {
            return 0;
        }
        if (i10 != 6) {
            return super.g(i10);
        }
        return -14539220;
    }

    @Override // mk.a
    public int h() {
        return this.f133608r;
    }

    @Override // mk.a
    public int i() {
        return this.f133611u;
    }

    @Override // mk.a
    public int j() {
        return this.f133610t;
    }

    @Override // mk.a
    public int k() {
        return KLineManager.f142490O.a().V() ? this.f133613w : this.f133612v;
    }

    @Override // mk.a
    public int n(int i10) {
        if (i10 == 0) {
            return -16492652;
        }
        if (i10 != 1) {
            return i10 != 2 ? 0 : -14969280;
        }
        return -3638749;
    }

    @Override // mk.a
    public int o() {
        return this.f133599B;
    }

    @Override // mk.a
    public int p() {
        return KLineManager.f142490O.a().V() ? this.f133612v : this.f133613w;
    }

    @Override // mk.a
    public int s() {
        return this.f133609s;
    }

    @Override // mk.a
    public int t() {
        return this.f133607q;
    }

    @Override // mk.b, mk.a
    public int u(int i10) {
        switch (i10) {
            case 1:
            case 3:
                return -7895161;
            case 2:
                return -5592406;
            case 4:
                return -8221287;
            case 5:
                return -10066330;
            case 6:
                return -1;
            case 7:
            case 8:
            case 9:
            default:
                return super.u(i10);
            case 10:
                return -15101570;
            case 11:
                return -5814153;
            case 12:
                return -9473152;
            case 13:
            case 14:
                return -1;
            case 15:
                return -5592406;
        }
    }

    @Override // mk.a
    public boolean w() {
        return this.f133600j;
    }

    @Override // mk.b
    public int y() {
        return this.f133603m;
    }

    @Override // mk.b
    public int z() {
        return this.f133604n;
    }
}
