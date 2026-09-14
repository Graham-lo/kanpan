package gk;

import Rj.C2732n;
import Sf.AbstractC2803q;
import java.util.List;

/* JADX INFO: loaded from: classes7.dex */
public final class C0 extends W {
    public C0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10);
    }

    @Override // gk.W
    public String D() {
        return "position";
    }

    @Override // gk.W
    public List E() {
        return AbstractC2803q.e("close");
    }
}
