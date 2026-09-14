package p398sh.aicoin.kline.winrate;

import Wf.d;
import app.aicoin.base.kline.data.WinRateSupport;
import org.json.JSONArray;
import org.json.JSONObject;
import p162hb.a;
import p167hg.F;
import p167hg.N;
import p229kg.c;
import p313og.k;
import p398sh.aicoin.app_base.net.util.b;
import p398sh.aicoin.app_base.net.util.e;
import p398sh.aicoin.base.model.f;
import p398sh.aicoin.base.vip.m;
import p398sh.aicoin.kline.tools.g;
import p398sh.aicoin.search.data.remote.SearchRemoteDataSource;

/* JADX INFO: loaded from: classes7.dex */
public final class w {

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public static final /* synthetic */ k[] f140750b = {N.h(new F(w.class, "url", "getUrl()Ljava/lang/String;", 0))};

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final c f140751a = com.aicoin.tools.network.host.c.d(com.aicoin.tools.network.host.c.f79143a, "/api/v5/kline/signal/support-list", null, 2, null);

    public static final JSONArray d(JSONObject jSONObject) {
        return jSONObject.optJSONArray(SearchRemoteDataSource.HTTP_PARSE_KEY_ITEM_LIST);
    }

    public final String b() {
        return (String) this.f140751a.getValue(this, f140750b[0]);
    }

    public Object c(String str, d dVar) {
        return e.b(f.f(m.f140510a, b(), b.b(g.a(a.f97739b)).a("symbol", str), null, 4, null), WinRateSupport.class, new v());
    }
}
