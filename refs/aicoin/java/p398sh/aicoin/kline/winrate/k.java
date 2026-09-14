package p398sh.aicoin.kline.winrate;

import Wf.d;
import Yf.b;
import org.json.JSONObject;
import p167hg.F;
import p167hg.N;
import p229kg.c;
import p398sh.aicoin.app_base.net.util.e;
import p398sh.aicoin.base.model.f;
import p398sh.aicoin.base.vip.m;

/* JADX INFO: loaded from: classes7.dex */
public final class k {

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public static final /* synthetic */ p313og.k[] f140727b = {N.h(new F(k.class, "url", "getUrl()Ljava/lang/String;", 0))};

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final c f140728a = com.aicoin.tools.network.host.c.d(com.aicoin.tools.network.host.c.f79143a, "/api/v5/kline/signal/minute-price", null, 2, null);

    public static final String d(JSONObject jSONObject) {
        return jSONObject.optString("close", "0");
    }

    public final String b() {
        return (String) this.f140728a.getValue(this, f140727b[0]);
    }

    public Object c(a aVar, d dVar) {
        return e.f(f.f(m.f140510a, b(), new lib.aicoin.net.json.f().a("symbol", aVar.a()).a("time", b.e(aVar.b())), null, 4, null), new j());
    }
}
