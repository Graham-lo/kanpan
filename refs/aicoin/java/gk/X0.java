package gk;

import Rj.C2732n;
import java.util.ArrayList;
import java.util.List;

/* JADX INFO: loaded from: classes7.dex */
public final class X0 extends AbstractC7467h0 {

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public final ArrayList f96493t;

    public X0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
        this.f96493t = new ArrayList();
    }

    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        super.A(sVar);
        this.f96493t.clear();
        this.f96493t.addAll(sVar.q().Y());
    }

    public final List D() {
        return this.f96493t;
    }
}
