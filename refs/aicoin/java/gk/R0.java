package gk;

import Rj.C2732n;
import java.util.List;
import kotlin.jvm.functions.Function1;

/* JADX INFO: loaded from: classes7.dex */
public final class R0 extends W {
    public R0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10);
    }

    public static final double H(double d10) {
        return d10 * ((double) 100);
    }

    @Override // gk.W
    public String D() {
        return "ttmu";
    }

    @Override // gk.W
    public List E() {
        return Sf.r.q("buyInterest", "sellInterest");
    }

    @Override // gk.W
    public Function1 G() {
        return new Q0();
    }
}
