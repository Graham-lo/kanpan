package p398sh.aicoin.kline.winrate;

import Qf.H;
import Wf.d;
import app.aicoin.base.kline.data.WinRateSupportCoinData;
import org.json.JSONArray;
import org.json.JSONObject;
import p167hg.F;
import p167hg.N;
import p229kg.c;
import p313og.k;
import p398sh.aicoin.app_base.net.util.e;
import p398sh.aicoin.base.model.f;
import p398sh.aicoin.base.vip.m;
import p398sh.aicoin.search.data.remote.SearchRemoteDataSource;

/* JADX INFO: loaded from: classes7.dex */
public final class u {

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public static final /* synthetic */ k[] f140748b = {N.h(new F(u.class, "url", "getUrl()Ljava/lang/String;", 0))};

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final c f140749a = com.aicoin.tools.network.host.c.d(com.aicoin.tools.network.host.c.f79143a, "/api/v5/kline/signal/support-coin", null, 2, null);

    public static final JSONArray d(JSONObject jSONObject) {
        return jSONObject.optJSONArray(SearchRemoteDataSource.HTTP_PARSE_KEY_ITEM_LIST);
    }

    public final String b() {
        return (String) this.f140749a.getValue(this, f140748b[0]);
    }

    public Object c(H h10, d dVar) {
        return e.b(f.f(m.f140510a, b(), new lib.aicoin.net.json.f(), null, 4, null), WinRateSupportCoinData.class, new t());
    }
}
