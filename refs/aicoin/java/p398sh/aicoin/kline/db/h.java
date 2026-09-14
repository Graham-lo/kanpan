package p398sh.aicoin.kline.db;

import P3.AbstractC2608f;
import P3.v;
import Qf.H;
import V3.j;
import app.aicoin.base.kline.data.WinRateConfigData;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import p049c4.d;

/* JADX INFO: loaded from: classes7.dex */
public final class h implements p398sh.aicoin.kline.db.a {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final v f140582a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final AbstractC2608f f140583b = new a();

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public final AbstractC2608f f140584c = new b();

    public class a extends AbstractC2608f {
        public a() {
        }

        @Override // P3.AbstractC2608f
        public String b() {
            return "INSERT OR REPLACE INTO `win_rate_config` (`key`,`cnName`,`enName`,`cnDescription`,`enDescription`,`coinStatus`,`termType`,`state`) VALUES (?,?,?,?,?,?,?,?)";
        }

        @Override // P3.AbstractC2608f
        /* JADX INFO: renamed from: f, reason: merged with bridge method [inline-methods] */
        public void a(d dVar, WinRateConfigData winRateConfigData) {
            if (winRateConfigData.getKey() == null) {
                dVar.bindNull(1);
            } else {
                dVar.H(1, winRateConfigData.getKey());
            }
            if (winRateConfigData.getCnName() == null) {
                dVar.bindNull(2);
            } else {
                dVar.H(2, winRateConfigData.getCnName());
            }
            if (winRateConfigData.getEnName() == null) {
                dVar.bindNull(3);
            } else {
                dVar.H(3, winRateConfigData.getEnName());
            }
            if (winRateConfigData.getCnDescription() == null) {
                dVar.bindNull(4);
            } else {
                dVar.H(4, winRateConfigData.getCnDescription());
            }
            if (winRateConfigData.getEnDescription() == null) {
                dVar.bindNull(5);
            } else {
                dVar.H(5, winRateConfigData.getEnDescription());
            }
            dVar.bindLong(6, winRateConfigData.getCoinStatus());
            if (winRateConfigData.getTermType() == null) {
                dVar.bindNull(7);
            } else {
                dVar.H(7, winRateConfigData.getTermType());
            }
            dVar.bindLong(8, winRateConfigData.getState());
        }
    }

    public class b extends AbstractC2608f {
        public b() {
        }

        @Override // P3.AbstractC2608f
        public String b() {
            return "INSERT OR REPLACE INTO `win_rate_select` (`key`,`isSelect`) VALUES (?,?)";
        }

        @Override // P3.AbstractC2608f
        /* JADX INFO: renamed from: f, reason: merged with bridge method [inline-methods] */
        public void a(d dVar, i iVar) {
            if (iVar.a() == null) {
                dVar.bindNull(1);
            } else {
                dVar.H(1, iVar.a());
            }
            dVar.bindLong(2, iVar.b() ? 1L : 0L);
        }
    }

    public h(v vVar) {
        this.f140582a = vVar;
    }

    public static /* synthetic */ List f(p049c4.b bVar) {
        d dVarV0 = bVar.V0("SELECT * FROM win_rate_config WHERE state == 1");
        try {
            int iC = j.c(dVarV0, "key");
            int iC2 = j.c(dVarV0, "cnName");
            int iC3 = j.c(dVarV0, "enName");
            int iC4 = j.c(dVarV0, "cnDescription");
            int iC5 = j.c(dVarV0, "enDescription");
            int iC6 = j.c(dVarV0, "coinStatus");
            int iC7 = j.c(dVarV0, "termType");
            int iC8 = j.c(dVarV0, "state");
            ArrayList arrayList = new ArrayList();
            while (dVarV0.T0()) {
                arrayList.add(new WinRateConfigData(dVarV0.isNull(iC) ? null : dVarV0.I0(iC), dVarV0.isNull(iC2) ? null : dVarV0.I0(iC2), dVarV0.isNull(iC3) ? null : dVarV0.I0(iC3), dVarV0.isNull(iC4) ? null : dVarV0.I0(iC4), dVarV0.isNull(iC5) ? null : dVarV0.I0(iC5), (int) dVarV0.getLong(iC6), dVarV0.isNull(iC7) ? null : dVarV0.I0(iC7), (int) dVarV0.getLong(iC8)));
            }
            return arrayList;
        } finally {
            dVarV0.close();
        }
    }

    public static /* synthetic */ List h(p049c4.b bVar) {
        d dVarV0 = bVar.V0("SELECT * FROM win_rate_select WHERE isSelect == 1");
        try {
            int iC = j.c(dVarV0, "key");
            int iC2 = j.c(dVarV0, "isSelect");
            ArrayList arrayList = new ArrayList();
            while (dVarV0.T0()) {
                arrayList.add(new i(dVarV0.isNull(iC) ? null : dVarV0.I0(iC), ((int) dVarV0.getLong(iC2)) != 0));
            }
            return arrayList;
        } finally {
            dVarV0.close();
        }
    }

    public static List i() {
        return Collections.EMPTY_LIST;
    }

    @Override // p398sh.aicoin.kline.db.a
    public Object a(List list, Wf.d dVar) {
        list.getClass();
        return V3.b.f(this.f140582a, false, true, new f(this, list), dVar);
    }

    @Override // p398sh.aicoin.kline.db.a
    public Object b(Wf.d dVar) {
        return V3.b.f(this.f140582a, true, false, new g(), dVar);
    }

    @Override // p398sh.aicoin.kline.db.a
    public Object c(i iVar, Wf.d dVar) {
        iVar.getClass();
        return V3.b.f(this.f140582a, false, true, new d(this, iVar), dVar);
    }

    @Override // p398sh.aicoin.kline.db.a
    public Object d(Wf.d dVar) {
        return V3.b.f(this.f140582a, true, false, new e(), dVar);
    }

    public final /* synthetic */ H j(List list, p049c4.b bVar) throws Exception {
        this.f140583b.c(bVar, list);
        return H.f17640a;
    }

    public final /* synthetic */ H k(i iVar, p049c4.b bVar) throws Exception {
        this.f140584c.d(bVar, iVar);
        return H.f17640a;
    }
}
