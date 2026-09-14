package p398sh.aicoin.kline.winrate;

import Ah.v;
import Ah.w;
import Dh.AbstractC1986i;
import Dh.C1979e0;
import Dh.O;
import Qf.H;
import Qf.s;
import Sf.r;
import Sf.z;
import Wf.d;
import Yf.l;
import com.google.gson.Gson;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import lib.aicoin.net.json.f;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import p146gg.o;
import p167hg.F;
import p167hg.N;
import p229kg.c;
import p313og.k;
import p398sh.aicoin.app_base.net.util.b;
import p398sh.aicoin.app_base.net.util.e;
import p398sh.aicoin.base.vip.m;
import p398sh.aicoin.kline.tools.g;
import p398sh.aicoin.search.data.remote.SearchRemoteDataSource;
import sp.aicoin_kline.chart.data.AIWinRateItem;

/* JADX INFO: loaded from: classes7.dex */
public final class WinRateSource {

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public static final /* synthetic */ k[] f140684c = {N.h(new F(WinRateSource.class, "url", "getUrl()Ljava/lang/String;", 0))};

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final c f140685a = com.aicoin.tools.network.host.c.d(com.aicoin.tools.network.host.c.f79143a, "/api/v5/kline/signal/kline-data", null, 2, null);

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final Gson f140686b = new Gson();

    public static final class a extends l implements o {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public int f140687a;

        /* JADX INFO: renamed from: c, reason: collision with root package name */
        public final /* synthetic */ p f140689c;

        /* JADX WARN: 'super' call moved to the top of the method (can break code semantics) */
        public a(p pVar, d dVar) {
            super(2, dVar);
            this.f140689c = pVar;
        }

        public static final q t(p pVar, WinRateSource winRateSource, JSONObject jSONObject) {
            String strOptString = jSONObject.optString("mapping");
            if (strOptString == null) {
                strOptString = "";
            }
            JSONArray jSONArrayOptJSONArray = jSONObject.optJSONArray(SearchRemoteDataSource.HTTP_PARSE_KEY_ITEM_LIST);
            return (jSONArrayOptJSONArray == null || jSONArrayOptJSONArray.length() < 1) ? new q(r.n(), true, 0L, pVar.c()) : winRateSource.d(strOptString, jSONArrayOptJSONArray, jSONObject.optBoolean("reset_status", true), pVar.c());
        }

        @Override // Yf.a
        public final d create(Object obj, d dVar) {
            return WinRateSource.this.new a(this.f140689c, dVar);
        }

        @Override // p146gg.o
        public final Object invoke(O o10, d dVar) {
            return ((a) create(o10, dVar)).invokeSuspend(H.f17640a);
        }

        @Override // Yf.a
        public final Object invokeSuspend(Object obj) throws Throwable {
            Xf.c.e();
            if (this.f140687a != 0) {
                throw new IllegalStateException("call to 'resume' before 'invoke' with coroutine");
            }
            s.b(obj);
            f fVarB = b.b(g.a(p162hb.a.f97739b));
            p pVar = this.f140689c;
            fVarB.a("symbol", pVar.c());
            fVarB.a("signals", new JSONArray((Collection) pVar.b()));
            if (pVar.a() > 0) {
                fVarB.a("latest_time", Yf.b.e(pVar.a()));
            }
            return e.f(p398sh.aicoin.base.model.f.f(m.f140510a, WinRateSource.this.f(), fVarB, null, 4, null), new s(this.f140689c, WinRateSource.this));
        }
    }

    public static final H e(JSONArray jSONArray, List list, WinRateSource winRateSource, List list2, int i10) throws JSONException {
        JSONArray jSONArray2 = jSONArray.getJSONArray(i10);
        AIWinRateItem aIWinRateItem = new AIWinRateItem(null, 0L, 0L, null, null, null, 0.0d, 0.0d, 0.0d, 0.0d, 0, null, false, 8191, null);
        int length = jSONArray2.length();
        for (int i11 = 0; i11 < length; i11++) {
            String str = (String) z.r0(list, i11);
            if (str == null) {
                return H.f17640a;
            }
            winRateSource.h(aIWinRateItem, str, jSONArray2.optString(i11));
        }
        list2.add(aIWinRateItem);
        return H.f17640a;
    }

    public final q d(String str, JSONArray jSONArray, boolean z10, String str2) {
        Object objFromJson;
        try {
            objFromJson = this.f140686b.fromJson(str, new WinRateSource$dealWinRateList$$inlined$fromJsonGenType$1().getType());
        } catch (Exception e10) {
            e10.printStackTrace();
            objFromJson = null;
        }
        List list = (List) objFromJson;
        if (list == null) {
            return new q(r.n(), true, 0L, str2);
        }
        ArrayList arrayList = new ArrayList();
        p398sh.aicoin.app_base.net.util.f.a(jSONArray, new r(jSONArray, list, this, arrayList));
        AIWinRateItem aIWinRateItem = (AIWinRateItem) z.q0(arrayList);
        return new q(arrayList, z10, aIWinRateItem != null ? aIWinRateItem.getSignal_time() : -1L, str2);
    }

    public final String f() {
        return (String) this.f140685a.getValue(this, f140684c[0]);
    }

    public Object g(p pVar, d dVar) {
        return AbstractC1986i.g(C1979e0.b(), new a(pVar, null), dVar);
    }

    /* JADX WARN: Failed to restore switch over string. Please report as a decompilation issue */
    public final void h(AIWinRateItem aIWinRateItem, String str, String str2) {
        switch (str.hashCode()) {
            case -2133380123:
                if (str.equals("advise_loss_rate")) {
                    Double dN = v.n(str2);
                    aIWinRateItem.setAdvise_loss_rate(dN != null ? dN.doubleValue() : 0.0d);
                    break;
                }
                break;
            case -612506382:
                if (str.equals("signal_price")) {
                    aIWinRateItem.setSignal_price(str2);
                    break;
                }
                break;
            case -444959058:
                if (str.equals("history_win_rate")) {
                    Double dN2 = v.n(str2);
                    aIWinRateItem.setHistory_win_rate(dN2 != null ? dN2.doubleValue() : 0.0d);
                    break;
                }
                break;
            case -275913385:
                if (str.equals("capital_rate")) {
                    Double dN3 = v.n(str2);
                    aIWinRateItem.setCapital_rate(dN3 != null ? dN3.doubleValue() : 0.0d);
                    break;
                }
                break;
            case 3355:
                if (str.equals("id")) {
                    aIWinRateItem.setId(str2);
                    break;
                }
                break;
            case 3530071:
                if (str.equals("side")) {
                    aIWinRateItem.setSide(str2);
                    break;
                }
                break;
            case 106934601:
                if (str.equals("price")) {
                    aIWinRateItem.setPrice(str2);
                    break;
                }
                break;
            case 109757585:
                if (str.equals("state")) {
                    Integer numP = w.p(str2);
                    aIWinRateItem.setState(numP != null ? numP.intValue() : -1);
                    break;
                }
                break;
            case 673089028:
                if (str.equals("signal_time")) {
                    Long lR = w.r(str2);
                    aIWinRateItem.setSignal_time(lR != null ? lR.longValue() : 0L);
                    aIWinRateItem.setSignal_time_s(aIWinRateItem.getSignal_time() / ((long) 1000));
                    break;
                }
                break;
            case 673104497:
                if (str.equals("signal_type")) {
                    aIWinRateItem.setSignal_type(str2);
                    break;
                }
                break;
            case 1700936410:
                if (str.equals("advise_win_rate")) {
                    Double dN4 = v.n(str2);
                    aIWinRateItem.setAdvise_win_rate(dN4 != null ? dN4.doubleValue() : 0.0d);
                    break;
                }
                break;
        }
    }
}
