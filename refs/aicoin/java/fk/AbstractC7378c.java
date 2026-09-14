package fk;

import sp.aicoin_kline.chart.data.LargeOrderInfo;
import sp.aicoin_kline.chart.data.LargeOrderItem;

/* JADX INFO: renamed from: fk.c, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public abstract class AbstractC7378c {
    public static final LargeOrderInfo a(LargeOrderItem largeOrderItem, int i10) {
        Double depth_amount_double = largeOrderItem.getDepth_amount_double();
        double dDoubleValue = depth_amount_double != null ? depth_amount_double.doubleValue() : 0.0d;
        String strValueOf = String.valueOf(i10);
        String depth_state = largeOrderItem.getDepth_state();
        if (depth_state == null) {
            depth_state = "";
        }
        String trade_type = largeOrderItem.getTrade_type();
        String str = trade_type == null ? "" : trade_type;
        String coin_type = largeOrderItem.getCoin_type();
        String str2 = coin_type == null ? "" : coin_type;
        String depth_type = largeOrderItem.getDepth_type();
        String str3 = depth_type == null ? "" : depth_type;
        Double depth_price_double = largeOrderItem.getDepth_price_double();
        String strValueOf2 = String.valueOf(depth_price_double != null ? depth_price_double.doubleValue() : 0.0d);
        String trade_amount = largeOrderItem.getTrade_amount();
        String str4 = trade_amount == null ? "" : trade_amount;
        String trade_turnover = largeOrderItem.getTrade_turnover();
        String str5 = trade_turnover == null ? "" : trade_turnover;
        String depth_amount = largeOrderItem.getDepth_amount();
        String str6 = depth_amount == null ? "" : depth_amount;
        String depth_turnover = largeOrderItem.getDepth_turnover();
        String str7 = depth_turnover == null ? "" : depth_turnover;
        Double trade_amount_double = largeOrderItem.getTrade_amount_double();
        String strValueOf3 = String.valueOf(nk.A.c(trade_amount_double != null ? trade_amount_double.doubleValue() : 0.0d, dDoubleValue, 0.0d) * ((double) 100));
        String trade_count = largeOrderItem.getTrade_count();
        String str8 = trade_count == null ? "" : trade_count;
        String high_trade_amount = largeOrderItem.getHigh_trade_amount();
        String str9 = high_trade_amount == null ? "" : high_trade_amount;
        String high_trade_turnover = largeOrderItem.getHigh_trade_turnover();
        String str10 = high_trade_turnover == null ? "" : high_trade_turnover;
        String position_sub = largeOrderItem.getPosition_sub();
        String str11 = position_sub == null ? "" : position_sub;
        String last_amount = largeOrderItem.getLast_amount();
        String str12 = last_amount == null ? "" : last_amount;
        String last_turnover = largeOrderItem.getLast_turnover();
        String str13 = last_turnover == null ? "" : last_turnover;
        String start_time = largeOrderItem.getStart_time();
        String str14 = start_time == null ? "" : start_time;
        String miss_time = largeOrderItem.getMiss_time();
        String str15 = miss_time == null ? "" : miss_time;
        String market_logo = largeOrderItem.getMarket_logo();
        String str16 = market_logo == null ? "" : market_logo;
        String market_name = largeOrderItem.getMarket_name();
        String str17 = market_name == null ? "" : market_name;
        String orderdownBound = largeOrderItem.getOrderdownBound();
        String str18 = orderdownBound == null ? "" : orderdownBound;
        String completedownBound = largeOrderItem.getCompletedownBound();
        return new LargeOrderInfo(strValueOf, depth_state, str, str2, str3, strValueOf2, str4, str5, str6, str7, strValueOf3, str8, str9, str10, str11, str12, str13, str14, str15, str16, str17, str18, completedownBound == null ? "" : completedownBound);
    }

    public static final boolean b(long j10, long j11, long j12, long j13) {
        if (j10 <= j13) {
            return j11 == 0 || j11 >= j12;
        }
        return false;
    }
}
