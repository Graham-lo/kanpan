package gk;

import Rj.C2732n;
import java.util.List;

/* JADX INFO: loaded from: classes7.dex */
public final class E extends W {
    public E(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10);
    }

    @Override // gk.W
    public String D() {
        return "bsv";
    }

    @Override // gk.W
    public List E() {
        return Sf.r.q("buyVolume", "sellVolume");
    }
}
