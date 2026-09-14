package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class d0 extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        TVolumeRemote tvolume = chartIndicatorSetting.getTvolume();
        if (tvolume == null) {
            return;
        }
        if (KLineManager.f142490O.a().H()) {
            TVolumeRemote.Output output = tvolume.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getTVolumeDisabled());
                return;
            }
            return;
        }
        TVolumeRemote.Output app_output = tvolume.getApp_output();
        if (app_output != null) {
            ek.v.l(this, 0, app_output.getTVolumeDisabled());
        }
        TVolumeRemote.Output output2 = tvolume.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getTVolumeDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new TVolumeRemote(new TVolumeRemote.Output(null, Boolean.valueOf(ek.v.j(this, 0, KLineManager.f142490O.a().H())), null, 5, null), new TVolumeRemote.Output(null, Boolean.valueOf(ek.v.g(this, 0)), null, 5, null)), null, null, null, null, null, null, null, null, null, null, null, null, null, -1, 33552383, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new TVolumeRemote(new TVolumeRemote.Output(null, Boolean.valueOf(ek.v.j(this, 0, z10)), null, 5, null), new TVolumeRemote.Output(null, Boolean.valueOf(ek.v.j(this, 0, z10)), null, 5, null)), null, null, null, null, null, null, null, null, null, null, null, null, null, -1, 33552383, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("tvolume");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 33;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("TVolume", -13643086, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[0];
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("TVolume", false, 2, null)};
    }
}
