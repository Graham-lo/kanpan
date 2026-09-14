package p398sh.aicoin.kline.winrate;

import Dh.AbstractC1986i;
import Dh.C1979e0;
import Dh.O;
import Qf.H;
import Qf.s;
import Wf.d;
import Yf.l;
import app.aicoin.base.kline.data.WinRateConfigData;
import org.json.JSONArray;
import org.json.JSONObject;
import p146gg.o;
import p167hg.F;
import p167hg.N;
import p229kg.c;
import p313og.k;
import p398sh.aicoin.app_base.net.util.b;
import p398sh.aicoin.app_base.net.util.e;
import p398sh.aicoin.base.model.f;
import p398sh.aicoin.base.vip.m;

/* JADX INFO: loaded from: classes7.dex */
public final class g {

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public static final /* synthetic */ k[] f140718b = {N.h(new F(g.class, "url", "getUrl()Ljava/lang/String;", 0))};

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final c f140719a = com.aicoin.tools.network.host.c.d(com.aicoin.tools.network.host.c.f79143a, "/api/v5/kline/signal/config", null, 2, null);

    public static final class a extends l implements o {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public int f140720a;

        public a(d dVar) {
            super(2, dVar);
        }

        /* JADX INFO: Access modifiers changed from: private */
        public static final JSONArray invokeSuspend$lambda$0(JSONObject jSONObject) {
            return jSONObject.optJSONArray("signal_type");
        }

        @Override // Yf.a
        public final d create(Object obj, d dVar) {
            return g.this.new a(dVar);
        }

        @Override // p146gg.o
        public final Object invoke(O o10, d dVar) {
            return ((a) create(o10, dVar)).invokeSuspend(H.f17640a);
        }

        @Override // Yf.a
        public final Object invokeSuspend(Object obj) throws Throwable {
            Xf.c.e();
            if (this.f140720a != 0) {
                throw new IllegalStateException("call to 'resume' before 'invoke' with coroutine");
            }
            s.b(obj);
            return e.b(f.f(m.f140510a, g.this.b(), b.b(p398sh.aicoin.kline.tools.g.a(p162hb.a.f97739b)).a("version", "v1"), null, 4, null), WinRateConfigData.class, new f());
        }
    }

    public final String b() {
        return (String) this.f140719a.getValue(this, f140718b[0]);
    }

    public Object c(H h10, d dVar) {
        return AbstractC1986i.g(C1979e0.b(), new a(null), dVar);
    }
}
