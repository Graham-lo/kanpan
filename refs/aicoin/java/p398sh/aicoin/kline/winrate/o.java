package p398sh.aicoin.kline.winrate;

import Qf.H;
import Sf.r;
import Wf.d;
import Xf.c;
import nk.n;
import p254m.aicoin.base.util.login.f;
import p398sh.aicoin.kline.db.a;
import p398sh.aicoin.kline.db.i;
import p398sh.aicoin.kline.tools.g;

/* JADX INFO: loaded from: classes7.dex */
public final class o implements n {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final a f140731a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final WinRateSource f140732b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public final k f140733c;

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public final h f140734d;

    public o(a aVar, WinRateSource winRateSource, k kVar, h hVar) {
        this.f140731a = aVar;
        this.f140732b = winRateSource;
        this.f140733c = kVar;
        this.f140734d = hVar;
    }

    @Override // p398sh.aicoin.kline.winrate.n
    public Object a(d dVar) {
        return this.f140731a.d(dVar);
    }

    @Override // p398sh.aicoin.kline.winrate.n
    public Object b(p pVar, d dVar) {
        return this.f140732b.g(pVar, dVar);
    }

    @Override // p398sh.aicoin.kline.winrate.n
    public Object c(d dVar) {
        return (f.f(g.a(p162hb.a.f97739b)) && n.f(23)) ? a(dVar) : r.n();
    }

    @Override // p398sh.aicoin.kline.winrate.n
    public Object d(i iVar, d dVar) {
        Object objC = this.f140731a.c(iVar, dVar);
        return objC == c.e() ? objC : H.f17640a;
    }

    @Override // p398sh.aicoin.kline.winrate.n
    public Object e(String str, long j10, d dVar) {
        return this.f140733c.c(new a(str, j10), dVar);
    }
}
