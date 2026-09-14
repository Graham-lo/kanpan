package sp.aicoin_kline.core.indicator.config;

import Qf.InterfaceC2632j;
import android.content.SharedPreferences;
import com.tencent.android.tpush.XGPushManager;
import kotlin.jvm.internal.DefaultConstructorMarker;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class V extends N {

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public static final a f142594r = new a(null);

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final InterfaceC2632j f142595m = Qf.k.b(new ek.E());

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final InterfaceC2632j f142596n = Qf.k.b(new ek.F(this));

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public boolean f142597o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public boolean f142598p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public boolean f142599q;

    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }
    }

    public static final String C(V v10) {
        return v10.n() + "_middle_band_disabled";
    }

    public static final SharedPreferences D() {
        return KLineManager.f142490O.a().i().getApplicationContext().getSharedPreferences("soso_kline_indicator_param", 0);
    }

    @Override // sp.aicoin_kline.core.indicator.config.N
    public ek.w[] A() {
        return new ek.w[]{new ek.w("MID", new p292ng.g(0, 100), 50, false, 0, 24, null), new ek.w("CEILING", new p292ng.g(0, 100), 70, false, 0, 24, null), new ek.w("FLOOR", new p292ng.g(0, 100), 30, false, 0, 24, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.N
    public N.a[] B() {
        return new N.a[]{new N.a("RSI1", new p292ng.g(0, 120), 6, true, -13643086, 2.0f), new N.a("RSI2", new p292ng.g(0, androidx.recyclerview.widget.l.e.DEFAULT_SWIPE_ANIMATION_DURATION), 12, true, -19456, 2.0f), new N.a("RSI3", new p292ng.g(0, XGPushManager.MAX_TAG_SIZE), 24, true, -1553991, 2.0f)};
    }

    public final boolean E() {
        if (!this.f142597o) {
            this.f142598p = ((SharedPreferences) this.f142595m.getValue()).getBoolean((String) this.f142596n.getValue(), false);
            this.f142597o = true;
        }
        return this.f142598p;
    }

    public final void F(Boolean bool) {
        if (bool != null) {
            this.f142597o = true;
            this.f142598p = bool.booleanValue();
            ((SharedPreferences) this.f142595m.getValue()).edit().putBoolean((String) this.f142596n.getValue(), bool.booleanValue()).apply();
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        Boolean middleBandDisabled;
        Boolean middleBandDisabled2;
        Boolean middleBandDisabled3;
        RsiRemote rsi = chartIndicatorSetting.getRsi();
        if (rsi == null) {
            return;
        }
        RsiRemote.Input input = rsi.getInput();
        if (input != null) {
            ek.v.m(this, 0, input.getMac1());
            ek.v.m(this, 1, input.getMac2());
            ek.v.m(this, 2, input.getMac3());
            ek.v.m(this, 4, input.getUpperBand());
            ek.v.m(this, 5, input.getLowerBand());
            ek.v.m(this, 3, input.getMiddleBand());
        }
        RsiRemote.Output app_output = rsi.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getRsi1LineColor());
            Integer rsi1LineWidth = app_output.getRsi1LineWidth();
            if (numR != null && rsi1LineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(rsi1LineWidth.intValue());
            }
            Integer numR2 = ek.v.r(app_output.getRsi2LineColor());
            Integer rsi2LineWidth = app_output.getRsi2LineWidth();
            if (numR2 != null && rsi2LineWidth != null) {
                k()[1].d(numR2.intValue());
                k()[1].e(rsi2LineWidth.intValue());
            }
            Integer numR3 = ek.v.r(app_output.getRsi3LineColor());
            Integer rsi3LineWidth = app_output.getRsi3LineWidth();
            if (numR3 != null && rsi3LineWidth != null) {
                k()[2].d(numR3.intValue());
                k()[2].e(rsi3LineWidth.intValue());
            }
        }
        Boolean middleBandDisabled4 = null;
        if (KLineManager.f142490O.a().H()) {
            RsiRemote.Input input2 = rsi.getInput();
            if (input2 != null) {
                ek.v.m(this, 0, input2.getMac1());
                ek.v.m(this, 1, input2.getMac2());
                ek.v.m(this, 2, input2.getMac3());
                ek.v.m(this, 4, input2.getUpperBand());
                ek.v.m(this, 5, input2.getLowerBand());
                ek.v.m(this, 3, input2.getMiddleBand());
            }
            RsiRemote.Output output = rsi.getOutput();
            if (output == null || (middleBandDisabled3 = output.getMiddleBandDisabled()) == null) {
                RsiRemote.Output app_output2 = rsi.getApp_output();
                if (app_output2 != null) {
                    middleBandDisabled4 = app_output2.getMiddleBandDisabled();
                }
            } else {
                middleBandDisabled4 = middleBandDisabled3;
            }
            F(middleBandDisabled4);
            return;
        }
        RsiRemote.Input app_input = rsi.getApp_input();
        if (app_input != null) {
            ek.v.m(this, 0, app_input.getMac1());
            ek.v.m(this, 1, app_input.getMac2());
            ek.v.m(this, 2, app_input.getMac3());
            ek.v.m(this, 4, app_input.getUpperBand());
            ek.v.m(this, 5, app_input.getLowerBand());
            ek.v.m(this, 3, app_input.getMiddleBand());
        }
        RsiRemote.Output app_output3 = rsi.getApp_output();
        if (app_output3 == null || (middleBandDisabled2 = app_output3.getMiddleBandDisabled()) == null) {
            RsiRemote.Output output2 = rsi.getOutput();
            if (output2 != null) {
                middleBandDisabled4 = output2.getMiddleBandDisabled();
            }
        } else {
            middleBandDisabled4 = middleBandDisabled2;
        }
        F(middleBandDisabled4);
        RsiRemote.Input input3 = rsi.getInput();
        if (input3 != null) {
            ek.v.p(this, 0, input3.getMac1());
            ek.v.p(this, 1, input3.getMac2());
            ek.v.p(this, 2, input3.getMac3());
            ek.v.p(this, 4, input3.getUpperBand());
            ek.v.p(this, 5, input3.getLowerBand());
            ek.v.p(this, 3, input3.getMiddleBand());
        }
        RsiRemote.Output output3 = rsi.getOutput();
        if (output3 == null || (middleBandDisabled = output3.getMiddleBandDisabled()) == null) {
            return;
        }
        this.f142599q = middleBandDisabled.booleanValue();
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        boolean zH = KLineManager.f142490O.a().H();
        RsiRemote.Input input = new RsiRemote.Input(Integer.valueOf(ek.v.i(this, 5, zH)), Integer.valueOf(ek.v.i(this, 3, zH)), Integer.valueOf(ek.v.i(this, 0, zH)), Integer.valueOf(ek.v.i(this, 1, zH)), Integer.valueOf(ek.v.i(this, 2, zH)), Integer.valueOf(ek.v.i(this, 4, zH)));
        RsiRemote.Output output = new RsiRemote.Output(null, null, null, null, null, Boolean.valueOf(zH ? E() : this.f142599q), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, 2097119, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new RsiRemote(input, output, new RsiRemote.Output(null, null, null, null, null, Boolean.valueOf(E()), null, null, null, null, strQ, Integer.valueOf(iB), null, ek.v.q(k()[1].a()), Integer.valueOf((int) k()[1].b()), null, ek.v.q(k()[2].a()), Integer.valueOf((int) k()[2].b()), null, null, null, 1872863, null), new RsiRemote.Input(Integer.valueOf(ek.v.f(this, 5)), Integer.valueOf(ek.v.f(this, 3)), Integer.valueOf(ek.v.f(this, 0)), Integer.valueOf(ek.v.f(this, 1)), Integer.valueOf(ek.v.f(this, 2)), Integer.valueOf(ek.v.f(this, 4)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -32769, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        RsiRemote.Input input = new RsiRemote.Input(Integer.valueOf(ek.v.i(this, 5, z10)), Integer.valueOf(ek.v.i(this, 3, z10)), Integer.valueOf(ek.v.i(this, 0, z10)), Integer.valueOf(ek.v.i(this, 1, z10)), Integer.valueOf(ek.v.i(this, 2, z10)), Integer.valueOf(ek.v.i(this, 4, z10)));
        RsiRemote.Output output = new RsiRemote.Output(null, null, null, null, null, Boolean.valueOf(z10 ? E() : this.f142599q), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, 2097119, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        String strQ2 = ek.v.q(k()[1].a());
        int iB2 = (int) k()[1].b();
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new RsiRemote(input, output, new RsiRemote.Output(null, null, null, null, null, Boolean.valueOf(z10 ? E() : this.f142599q), null, null, null, null, strQ, Integer.valueOf(iB), null, strQ2, Integer.valueOf(iB2), null, ek.v.q(k()[2].a()), Integer.valueOf((int) k()[2].b()), null, null, null, 1872863, null), new RsiRemote.Input(Integer.valueOf(ek.v.i(this, 5, z10)), Integer.valueOf(ek.v.i(this, 3, z10)), Integer.valueOf(ek.v.i(this, 0, z10)), Integer.valueOf(ek.v.i(this, 1, z10)), Integer.valueOf(ek.v.i(this, 2, z10)), Integer.valueOf(ek.v.i(this, 4, z10)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -32769, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("rsi");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 3;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }
}
