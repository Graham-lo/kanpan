package sp.aicoin_kline.chart.data;

import androidx.annotation.Keep;
import kk.d;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import okhttp3.internal.http2.Http2;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\bB\n\u0002\u0010\u000b\n\u0002\b\u0004\b\u0087\b\u0018\u00002\u00020\u0001B\u009d\u0001\u0012\b\b\u0002\u0010\u0002\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0004\u001a\u00020\u0005\u0012\b\b\u0002\u0010\u0006\u001a\u00020\u0005\u0012\b\b\u0002\u0010\u0007\u001a\u00020\u0005\u0012\b\b\u0002\u0010\b\u001a\u00020\u0005\u0012\b\b\u0002\u0010\t\u001a\u00020\u0005\u0012\b\b\u0002\u0010\n\u001a\u00020\u0005\u0012\b\b\u0002\u0010\u000b\u001a\u00020\u0005\u0012\b\b\u0002\u0010\f\u001a\u00020\u0005\u0012\b\b\u0002\u0010\r\u001a\u00020\u0005\u0012\b\b\u0002\u0010\u000e\u001a\u00020\u0005\u0012\b\b\u0002\u0010\u000f\u001a\u00020\u0005\u0012\b\b\u0002\u0010\u0010\u001a\u00020\u0005\u0012\b\b\u0002\u0010\u0011\u001a\u00020\u0005\u0012\b\b\u0002\u0010\u0012\u001a\u00020\u0005¢\u0006\u0004\b\u0013\u0010\u0014J\t\u00107\u001a\u00020\u0003HÆ\u0003J\t\u00108\u001a\u00020\u0005HÆ\u0003J\t\u00109\u001a\u00020\u0005HÆ\u0003J\t\u0010:\u001a\u00020\u0005HÆ\u0003J\t\u0010;\u001a\u00020\u0005HÆ\u0003J\t\u0010<\u001a\u00020\u0005HÆ\u0003J\t\u0010=\u001a\u00020\u0005HÆ\u0003J\t\u0010>\u001a\u00020\u0005HÆ\u0003J\t\u0010?\u001a\u00020\u0005HÆ\u0003J\t\u0010@\u001a\u00020\u0005HÆ\u0003J\t\u0010A\u001a\u00020\u0005HÆ\u0003J\t\u0010B\u001a\u00020\u0005HÆ\u0003J\t\u0010C\u001a\u00020\u0005HÆ\u0003J\t\u0010D\u001a\u00020\u0005HÆ\u0003J\t\u0010E\u001a\u00020\u0005HÆ\u0003J\u009f\u0001\u0010F\u001a\u00020\u00002\b\b\u0002\u0010\u0002\u001a\u00020\u00032\b\b\u0002\u0010\u0004\u001a\u00020\u00052\b\b\u0002\u0010\u0006\u001a\u00020\u00052\b\b\u0002\u0010\u0007\u001a\u00020\u00052\b\b\u0002\u0010\b\u001a\u00020\u00052\b\b\u0002\u0010\t\u001a\u00020\u00052\b\b\u0002\u0010\n\u001a\u00020\u00052\b\b\u0002\u0010\u000b\u001a\u00020\u00052\b\b\u0002\u0010\f\u001a\u00020\u00052\b\b\u0002\u0010\r\u001a\u00020\u00052\b\b\u0002\u0010\u000e\u001a\u00020\u00052\b\b\u0002\u0010\u000f\u001a\u00020\u00052\b\b\u0002\u0010\u0010\u001a\u00020\u00052\b\b\u0002\u0010\u0011\u001a\u00020\u00052\b\b\u0002\u0010\u0012\u001a\u00020\u0005HÆ\u0001J\u0013\u0010G\u001a\u00020H2\b\u0010I\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010J\u001a\u00020\u0003HÖ\u0001J\t\u0010K\u001a\u00020\u0005HÖ\u0001R\u001a\u0010\u0002\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u0015\u0010\u0016\"\u0004\b\u0017\u0010\u0018R\u001a\u0010\u0004\u001a\u00020\u0005X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u0019\u0010\u001a\"\u0004\b\u001b\u0010\u001cR\u001a\u0010\u0006\u001a\u00020\u0005X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u001d\u0010\u001a\"\u0004\b\u001e\u0010\u001cR\u001a\u0010\u0007\u001a\u00020\u0005X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u001f\u0010\u001a\"\u0004\b \u0010\u001cR\u001a\u0010\b\u001a\u00020\u0005X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b!\u0010\u001a\"\u0004\b\"\u0010\u001cR\u001a\u0010\t\u001a\u00020\u0005X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b#\u0010\u001a\"\u0004\b$\u0010\u001cR\u001a\u0010\n\u001a\u00020\u0005X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b%\u0010\u001a\"\u0004\b&\u0010\u001cR\u001a\u0010\u000b\u001a\u00020\u0005X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b'\u0010\u001a\"\u0004\b(\u0010\u001cR\u001a\u0010\f\u001a\u00020\u0005X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b)\u0010\u001a\"\u0004\b*\u0010\u001cR\u001a\u0010\r\u001a\u00020\u0005X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b+\u0010\u001a\"\u0004\b,\u0010\u001cR\u001a\u0010\u000e\u001a\u00020\u0005X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b-\u0010\u001a\"\u0004\b.\u0010\u001cR\u001a\u0010\u000f\u001a\u00020\u0005X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b/\u0010\u001a\"\u0004\b0\u0010\u001cR\u001a\u0010\u0010\u001a\u00020\u0005X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b1\u0010\u001a\"\u0004\b2\u0010\u001cR\u001a\u0010\u0011\u001a\u00020\u0005X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b3\u0010\u001a\"\u0004\b4\u0010\u001cR\u001a\u0010\u0012\u001a\u00020\u0005X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b5\u0010\u001a\"\u0004\b6\u0010\u001c¨\u0006L"}, d2 = {"Lsp/aicoin_kline/chart/data/LargeTradeInfo;", "", "x", "", "coin_type", "", "trade_type", "start_price", "stop_price", "max_price", "max_price_usd", "slippage_price", "max_amount", "max_vol", "total_amount", "total_vol", "total_count", "total_turnover", "update_time", "<init>", "(ILjava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V", "getX", "()I", "setX", "(I)V", "getCoin_type", "()Ljava/lang/String;", "setCoin_type", "(Ljava/lang/String;)V", "getTrade_type", "setTrade_type", "getStart_price", "setStart_price", "getStop_price", "setStop_price", "getMax_price", "setMax_price", "getMax_price_usd", "setMax_price_usd", "getSlippage_price", "setSlippage_price", "getMax_amount", "setMax_amount", "getMax_vol", "setMax_vol", "getTotal_amount", "setTotal_amount", "getTotal_vol", "setTotal_vol", "getTotal_count", "setTotal_count", "getTotal_turnover", "setTotal_turnover", "getUpdate_time", "setUpdate_time", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "component9", "component10", "component11", "component12", "component13", "component14", "component15", "copy", "equals", "", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class LargeTradeInfo {
    private String coin_type;
    private String max_amount;
    private String max_price;
    private String max_price_usd;
    private String max_vol;
    private String slippage_price;
    private String start_price;
    private String stop_price;
    private String total_amount;
    private String total_count;
    private String total_turnover;
    private String total_vol;
    private String trade_type;
    private String update_time;
    private int x;

    public LargeTradeInfo() {
        this(0, null, null, null, null, null, null, null, null, null, null, null, null, null, null, 32767, null);
    }

    public LargeTradeInfo(int i10, String str, String str2, String str3, String str4, String str5, String str6, String str7, String str8, String str9, String str10, String str11, String str12, String str13, String str14) {
        this.x = i10;
        this.coin_type = str;
        this.trade_type = str2;
        this.start_price = str3;
        this.stop_price = str4;
        this.max_price = str5;
        this.max_price_usd = str6;
        this.slippage_price = str7;
        this.max_amount = str8;
        this.max_vol = str9;
        this.total_amount = str10;
        this.total_vol = str11;
        this.total_count = str12;
        this.total_turnover = str13;
        this.update_time = str14;
    }

    public /* synthetic */ LargeTradeInfo(int i10, String str, String str2, String str3, String str4, String str5, String str6, String str7, String str8, String str9, String str10, String str11, String str12, String str13, String str14, int i11, DefaultConstructorMarker defaultConstructorMarker) {
        this((i11 & 1) != 0 ? 0 : i10, (i11 & 2) != 0 ? "" : str, (i11 & 4) != 0 ? "" : str2, (i11 & 8) != 0 ? "" : str3, (i11 & 16) != 0 ? "" : str4, (i11 & 32) != 0 ? "" : str5, (i11 & 64) != 0 ? "" : str6, (i11 & 128) != 0 ? "" : str7, (i11 & 256) != 0 ? "" : str8, (i11 & 512) != 0 ? "" : str9, (i11 & 1024) != 0 ? "" : str10, (i11 & 2048) != 0 ? "" : str11, (i11 & 4096) != 0 ? "" : str12, (i11 & 8192) != 0 ? "" : str13, (i11 & Http2.INITIAL_MAX_FRAME_SIZE) != 0 ? "" : str14);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final int getX() {
        return this.x;
    }

    /* JADX INFO: renamed from: component10, reason: from getter */
    public final String getMax_vol() {
        return this.max_vol;
    }

    /* JADX INFO: renamed from: component11, reason: from getter */
    public final String getTotal_amount() {
        return this.total_amount;
    }

    /* JADX INFO: renamed from: component12, reason: from getter */
    public final String getTotal_vol() {
        return this.total_vol;
    }

    /* JADX INFO: renamed from: component13, reason: from getter */
    public final String getTotal_count() {
        return this.total_count;
    }

    /* JADX INFO: renamed from: component14, reason: from getter */
    public final String getTotal_turnover() {
        return this.total_turnover;
    }

    /* JADX INFO: renamed from: component15, reason: from getter */
    public final String getUpdate_time() {
        return this.update_time;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final String getCoin_type() {
        return this.coin_type;
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    public final String getTrade_type() {
        return this.trade_type;
    }

    /* JADX INFO: renamed from: component4, reason: from getter */
    public final String getStart_price() {
        return this.start_price;
    }

    /* JADX INFO: renamed from: component5, reason: from getter */
    public final String getStop_price() {
        return this.stop_price;
    }

    /* JADX INFO: renamed from: component6, reason: from getter */
    public final String getMax_price() {
        return this.max_price;
    }

    /* JADX INFO: renamed from: component7, reason: from getter */
    public final String getMax_price_usd() {
        return this.max_price_usd;
    }

    /* JADX INFO: renamed from: component8, reason: from getter */
    public final String getSlippage_price() {
        return this.slippage_price;
    }

    /* JADX INFO: renamed from: component9, reason: from getter */
    public final String getMax_amount() {
        return this.max_amount;
    }

    public final LargeTradeInfo copy(int x10, String coin_type, String trade_type, String start_price, String stop_price, String max_price, String max_price_usd, String slippage_price, String max_amount, String max_vol, String total_amount, String total_vol, String total_count, String total_turnover, String update_time) {
        return new LargeTradeInfo(x10, coin_type, trade_type, start_price, stop_price, max_price, max_price_usd, slippage_price, max_amount, max_vol, total_amount, total_vol, total_count, total_turnover, update_time);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof LargeTradeInfo)) {
            return false;
        }
        LargeTradeInfo largeTradeInfo = (LargeTradeInfo) other;
        return this.x == largeTradeInfo.x && AbstractC7609s.f(this.coin_type, largeTradeInfo.coin_type) && AbstractC7609s.f(this.trade_type, largeTradeInfo.trade_type) && AbstractC7609s.f(this.start_price, largeTradeInfo.start_price) && AbstractC7609s.f(this.stop_price, largeTradeInfo.stop_price) && AbstractC7609s.f(this.max_price, largeTradeInfo.max_price) && AbstractC7609s.f(this.max_price_usd, largeTradeInfo.max_price_usd) && AbstractC7609s.f(this.slippage_price, largeTradeInfo.slippage_price) && AbstractC7609s.f(this.max_amount, largeTradeInfo.max_amount) && AbstractC7609s.f(this.max_vol, largeTradeInfo.max_vol) && AbstractC7609s.f(this.total_amount, largeTradeInfo.total_amount) && AbstractC7609s.f(this.total_vol, largeTradeInfo.total_vol) && AbstractC7609s.f(this.total_count, largeTradeInfo.total_count) && AbstractC7609s.f(this.total_turnover, largeTradeInfo.total_turnover) && AbstractC7609s.f(this.update_time, largeTradeInfo.update_time);
    }

    public final String getCoin_type() {
        return this.coin_type;
    }

    public final String getMax_amount() {
        return this.max_amount;
    }

    public final String getMax_price() {
        return this.max_price;
    }

    public final String getMax_price_usd() {
        return this.max_price_usd;
    }

    public final String getMax_vol() {
        return this.max_vol;
    }

    public final String getSlippage_price() {
        return this.slippage_price;
    }

    public final String getStart_price() {
        return this.start_price;
    }

    public final String getStop_price() {
        return this.stop_price;
    }

    public final String getTotal_amount() {
        return this.total_amount;
    }

    public final String getTotal_count() {
        return this.total_count;
    }

    public final String getTotal_turnover() {
        return this.total_turnover;
    }

    public final String getTotal_vol() {
        return this.total_vol;
    }

    public final String getTrade_type() {
        return this.trade_type;
    }

    public final String getUpdate_time() {
        return this.update_time;
    }

    public final int getX() {
        return this.x;
    }

    public int hashCode() {
        return this.update_time.hashCode() + d.a(this.total_turnover, d.a(this.total_count, d.a(this.total_vol, d.a(this.total_amount, d.a(this.max_vol, d.a(this.max_amount, d.a(this.slippage_price, d.a(this.max_price_usd, d.a(this.max_price, d.a(this.stop_price, d.a(this.start_price, d.a(this.trade_type, d.a(this.coin_type, Integer.hashCode(this.x) * 31, 31), 31), 31), 31), 31), 31), 31), 31), 31), 31), 31), 31), 31);
    }

    public final void setCoin_type(String str) {
        this.coin_type = str;
    }

    public final void setMax_amount(String str) {
        this.max_amount = str;
    }

    public final void setMax_price(String str) {
        this.max_price = str;
    }

    public final void setMax_price_usd(String str) {
        this.max_price_usd = str;
    }

    public final void setMax_vol(String str) {
        this.max_vol = str;
    }

    public final void setSlippage_price(String str) {
        this.slippage_price = str;
    }

    public final void setStart_price(String str) {
        this.start_price = str;
    }

    public final void setStop_price(String str) {
        this.stop_price = str;
    }

    public final void setTotal_amount(String str) {
        this.total_amount = str;
    }

    public final void setTotal_count(String str) {
        this.total_count = str;
    }

    public final void setTotal_turnover(String str) {
        this.total_turnover = str;
    }

    public final void setTotal_vol(String str) {
        this.total_vol = str;
    }

    public final void setTrade_type(String str) {
        this.trade_type = str;
    }

    public final void setUpdate_time(String str) {
        this.update_time = str;
    }

    public final void setX(int i10) {
        this.x = i10;
    }

    public String toString() {
        return "LargeTradeInfo(x=" + this.x + ", coin_type=" + this.coin_type + ", trade_type=" + this.trade_type + ", start_price=" + this.start_price + ", stop_price=" + this.stop_price + ", max_price=" + this.max_price + ", max_price_usd=" + this.max_price_usd + ", slippage_price=" + this.slippage_price + ", max_amount=" + this.max_amount + ", max_vol=" + this.max_vol + ", total_amount=" + this.total_amount + ", total_vol=" + this.total_vol + ", total_count=" + this.total_count + ", total_turnover=" + this.total_turnover + ", update_time=" + this.update_time + ')';
    }
}
