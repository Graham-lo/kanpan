package gk;

import com.umeng.commonsdk.statistics.SdkVersion;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.chart.data.LargeOrderItem;

/* JADX INFO: renamed from: gk.j, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public abstract class AbstractC7470j {
    public static final boolean a(LargeOrderItem largeOrderItem) {
        return AbstractC7609s.f(largeOrderItem.getDepth_state(), "0") || AbstractC7609s.f(largeOrderItem.getDepth_state(), SdkVersion.MINI_VERSION);
    }

    public static final Qf.p b(LargeOrderItem largeOrderItem) {
        String id2 = largeOrderItem.getId();
        if (id2 != null) {
            if (Ah.y.j0(id2)) {
                id2 = null;
            }
            if (id2 != null) {
                String platform = largeOrderItem.getPlatform();
                if (platform == null) {
                    platform = "";
                }
                return Qf.w.a(platform, id2);
            }
        }
        return null;
    }

    public static final C7486r0 c(dk.s sVar) {
        Sj.a aVarC = sVar.q().C();
        Sj.b bVar = (Sj.b) Sf.z.r0(aVarC, 0);
        long jE = bVar != null ? bVar.e() : 0L;
        Sj.b bVar2 = (Sj.b) Sf.z.r0(aVarC, 1);
        return new C7486r0(jE, (bVar2 != null ? bVar2.e() : 0L) - jE);
    }

    /* JADX WARN: Code duplicated, block: B:47:0x00bd  */
    public static final void d(LargeOrderItem largeOrderItem, C7486r0 c7486r0) {
        Double dN;
        Double dN2;
        int iP;
        Double dN3;
        long jR;
        long jValueOf;
        Long lR;
        Double dN4;
        String fake_price = largeOrderItem.getFake_price();
        Double dValueOf = Double.valueOf(0.0d);
        if (fake_price == null || (dN = Ah.v.n(fake_price)) == null) {
            dN = dValueOf;
        }
        largeOrderItem.setFake_price_double(dN);
        String depth_price = largeOrderItem.getDepth_price();
        if (depth_price == null || (dN2 = Ah.v.n(depth_price)) == null) {
            dN2 = dValueOf;
        }
        largeOrderItem.setDepth_price_double(dN2);
        String depth_state = largeOrderItem.getDepth_state();
        if (depth_state == null || (iP = Ah.w.p(depth_state)) == null) {
            iP = 0;
        }
        largeOrderItem.setDepth_state_int(iP);
        String trade_amount = largeOrderItem.getTrade_amount();
        if (trade_amount == null || (dN3 = Ah.v.n(trade_amount)) == null) {
            dN3 = dValueOf;
        }
        largeOrderItem.setTrade_amount_double(dN3);
        String depth_amount = largeOrderItem.getDepth_amount();
        if (depth_amount != null && (dN4 = Ah.v.n(depth_amount)) != null) {
            dValueOf = dN4;
        }
        largeOrderItem.setDepth_amount_double(dValueOf);
        String miss_time = largeOrderItem.getMiss_time();
        if (miss_time == null || (jR = Ah.w.r(miss_time)) == null) {
            jR = 0L;
        }
        largeOrderItem.setMiss_time_long(jR);
        String start_time = largeOrderItem.getStart_time();
        largeOrderItem.setDraw_start_time(Long.valueOf(e((start_time == null || (lR = Ah.w.r(start_time)) == null) ? 0L : lR.longValue(), c7486r0.c(), c7486r0.b())));
        Long miss_time_long = largeOrderItem.getMiss_time_long();
        if (miss_time_long == null) {
            jValueOf = 0L;
        } else {
            if (miss_time_long.longValue() == 0) {
                miss_time_long = null;
            }
            if (miss_time_long != null) {
                jValueOf = Long.valueOf(e(miss_time_long.longValue(), c7486r0.c(), c7486r0.b()));
            } else {
                jValueOf = 0L;
            }
        }
        largeOrderItem.setDraw_miss_time(jValueOf);
    }

    public static final long e(long j10, long j11, long j12) {
        if (j12 <= 0) {
            return 0L;
        }
        return ((j12 / 1000) * ((long) nk.w.f134250a.k(j12, j11, j10))) + (j11 / 1000);
    }

    public static final boolean f(LargeOrderItem largeOrderItem) {
        String show_state;
        Integer numP;
        return ((largeOrderItem == null || (show_state = largeOrderItem.getShow_state()) == null || (numP = Ah.w.p(show_state)) == null) ? 0 : numP.intValue()) != 0;
    }
}
