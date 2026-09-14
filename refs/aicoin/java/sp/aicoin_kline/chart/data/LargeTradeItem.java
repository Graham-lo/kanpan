package sp.aicoin_kline.chart.data;

import androidx.annotation.Keep;
import kk.d;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import okhttp3.dnsoverhttps.DnsOverHttps;
import okhttp3.internal.http2.Http2;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000*\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0011\n\u0002\u0010\t\n\u0002\b>\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0002\b\u0002\b\u0087\b\u0018\u00002\u00020\u0001B»\u0001\u0012\b\b\u0002\u0010\u0002\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0004\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0005\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0006\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0007\u001a\u00020\u0003\u0012\b\b\u0002\u0010\b\u001a\u00020\u0003\u0012\b\b\u0002\u0010\t\u001a\u00020\u0003\u0012\b\b\u0002\u0010\n\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u000b\u001a\u00020\u0003\u0012\b\b\u0002\u0010\f\u001a\u00020\u0003\u0012\b\b\u0002\u0010\r\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u000e\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u000f\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0010\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0011\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0012\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0013\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0014\u001a\u00020\u0015¢\u0006\u0004\b\u0016\u0010\u0017J\t\u0010@\u001a\u00020\u0003HÆ\u0003J\t\u0010A\u001a\u00020\u0003HÆ\u0003J\t\u0010B\u001a\u00020\u0003HÆ\u0003J\t\u0010C\u001a\u00020\u0003HÆ\u0003J\t\u0010D\u001a\u00020\u0003HÆ\u0003J\t\u0010E\u001a\u00020\u0003HÆ\u0003J\t\u0010F\u001a\u00020\u0003HÆ\u0003J\t\u0010G\u001a\u00020\u0003HÆ\u0003J\t\u0010H\u001a\u00020\u0003HÆ\u0003J\t\u0010I\u001a\u00020\u0003HÆ\u0003J\t\u0010J\u001a\u00020\u0003HÆ\u0003J\t\u0010K\u001a\u00020\u0003HÆ\u0003J\t\u0010L\u001a\u00020\u0003HÆ\u0003J\t\u0010M\u001a\u00020\u0003HÆ\u0003J\t\u0010N\u001a\u00020\u0003HÆ\u0003J\t\u0010O\u001a\u00020\u0003HÆ\u0003J\t\u0010P\u001a\u00020\u0003HÆ\u0003J\t\u0010Q\u001a\u00020\u0015HÆ\u0003J½\u0001\u0010R\u001a\u00020\u00002\b\b\u0002\u0010\u0002\u001a\u00020\u00032\b\b\u0002\u0010\u0004\u001a\u00020\u00032\b\b\u0002\u0010\u0005\u001a\u00020\u00032\b\b\u0002\u0010\u0006\u001a\u00020\u00032\b\b\u0002\u0010\u0007\u001a\u00020\u00032\b\b\u0002\u0010\b\u001a\u00020\u00032\b\b\u0002\u0010\t\u001a\u00020\u00032\b\b\u0002\u0010\n\u001a\u00020\u00032\b\b\u0002\u0010\u000b\u001a\u00020\u00032\b\b\u0002\u0010\f\u001a\u00020\u00032\b\b\u0002\u0010\r\u001a\u00020\u00032\b\b\u0002\u0010\u000e\u001a\u00020\u00032\b\b\u0002\u0010\u000f\u001a\u00020\u00032\b\b\u0002\u0010\u0010\u001a\u00020\u00032\b\b\u0002\u0010\u0011\u001a\u00020\u00032\b\b\u0002\u0010\u0012\u001a\u00020\u00032\b\b\u0002\u0010\u0013\u001a\u00020\u00032\b\b\u0002\u0010\u0014\u001a\u00020\u0015HÆ\u0001J\u0013\u0010S\u001a\u00020T2\b\u0010U\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010V\u001a\u00020WHÖ\u0001J\t\u0010X\u001a\u00020\u0003HÖ\u0001R\u001a\u0010\u0002\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u0018\u0010\u0019\"\u0004\b\u001a\u0010\u001bR\u001a\u0010\u0004\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u001c\u0010\u0019\"\u0004\b\u001d\u0010\u001bR\u001a\u0010\u0005\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u001e\u0010\u0019\"\u0004\b\u001f\u0010\u001bR\u001a\u0010\u0006\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b \u0010\u0019\"\u0004\b!\u0010\u001bR\u001a\u0010\u0007\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\"\u0010\u0019\"\u0004\b#\u0010\u001bR\u001a\u0010\b\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b$\u0010\u0019\"\u0004\b%\u0010\u001bR\u001a\u0010\t\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b&\u0010\u0019\"\u0004\b'\u0010\u001bR\u001a\u0010\n\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b(\u0010\u0019\"\u0004\b)\u0010\u001bR\u001a\u0010\u000b\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b*\u0010\u0019\"\u0004\b+\u0010\u001bR\u001a\u0010\f\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b,\u0010\u0019\"\u0004\b-\u0010\u001bR\u001a\u0010\r\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b.\u0010\u0019\"\u0004\b/\u0010\u001bR\u001a\u0010\u000e\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b0\u0010\u0019\"\u0004\b1\u0010\u001bR\u001a\u0010\u000f\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b2\u0010\u0019\"\u0004\b3\u0010\u001bR\u001a\u0010\u0010\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b4\u0010\u0019\"\u0004\b5\u0010\u001bR\u001a\u0010\u0011\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b6\u0010\u0019\"\u0004\b7\u0010\u001bR\u001a\u0010\u0012\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b8\u0010\u0019\"\u0004\b9\u0010\u001bR\u001a\u0010\u0013\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b:\u0010\u0019\"\u0004\b;\u0010\u001bR\u001a\u0010\u0014\u001a\u00020\u0015X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b<\u0010=\"\u0004\b>\u0010?¨\u0006Y"}, d2 = {"Lsp/aicoin_kline/chart/data/LargeTradeItem;", "", "timestamp", "", "id", "coin_type", "trade_type", "start_price", "stop_price", "max_price", "max_price_usd", "slippage_price", "max_amount", "max_vol", "total_amount", "total_vol", "total_count", "total_turnover", "n", "update_time", "draw_time", "", "<init>", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;J)V", "getTimestamp", "()Ljava/lang/String;", "setTimestamp", "(Ljava/lang/String;)V", "getId", "setId", "getCoin_type", "setCoin_type", "getTrade_type", "setTrade_type", "getStart_price", "setStart_price", "getStop_price", "setStop_price", "getMax_price", "setMax_price", "getMax_price_usd", "setMax_price_usd", "getSlippage_price", "setSlippage_price", "getMax_amount", "setMax_amount", "getMax_vol", "setMax_vol", "getTotal_amount", "setTotal_amount", "getTotal_vol", "setTotal_vol", "getTotal_count", "setTotal_count", "getTotal_turnover", "setTotal_turnover", "getN", "setN", "getUpdate_time", "setUpdate_time", "getDraw_time", "()J", "setDraw_time", "(J)V", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "component9", "component10", "component11", "component12", "component13", "component14", "component15", "component16", "component17", "component18", "copy", "equals", "", "other", "hashCode", "", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class LargeTradeItem {
    private String coin_type;
    private long draw_time;
    private String id;
    private String max_amount;
    private String max_price;
    private String max_price_usd;
    private String max_vol;
    private String n;
    private String slippage_price;
    private String start_price;
    private String stop_price;
    private String timestamp;
    private String total_amount;
    private String total_count;
    private String total_turnover;
    private String total_vol;
    private String trade_type;
    private String update_time;

    public LargeTradeItem() {
        this(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, 0L, 262143, null);
    }

    public LargeTradeItem(String str, String str2, String str3, String str4, String str5, String str6, String str7, String str8, String str9, String str10, String str11, String str12, String str13, String str14, String str15, String str16, String str17, long j10) {
        this.timestamp = str;
        this.id = str2;
        this.coin_type = str3;
        this.trade_type = str4;
        this.start_price = str5;
        this.stop_price = str6;
        this.max_price = str7;
        this.max_price_usd = str8;
        this.slippage_price = str9;
        this.max_amount = str10;
        this.max_vol = str11;
        this.total_amount = str12;
        this.total_vol = str13;
        this.total_count = str14;
        this.total_turnover = str15;
        this.n = str16;
        this.update_time = str17;
        this.draw_time = j10;
    }

    public /* synthetic */ LargeTradeItem(String str, String str2, String str3, String str4, String str5, String str6, String str7, String str8, String str9, String str10, String str11, String str12, String str13, String str14, String str15, String str16, String str17, long j10, int i10, DefaultConstructorMarker defaultConstructorMarker) {
        this((i10 & 1) != 0 ? "" : str, (i10 & 2) != 0 ? "" : str2, (i10 & 4) != 0 ? "" : str3, (i10 & 8) != 0 ? "" : str4, (i10 & 16) != 0 ? "" : str5, (i10 & 32) != 0 ? "" : str6, (i10 & 64) != 0 ? "" : str7, (i10 & 128) != 0 ? "" : str8, (i10 & 256) != 0 ? "" : str9, (i10 & 512) != 0 ? "" : str10, (i10 & 1024) != 0 ? "" : str11, (i10 & 2048) != 0 ? "" : str12, (i10 & 4096) != 0 ? "" : str13, (i10 & 8192) != 0 ? "" : str14, (i10 & Http2.INITIAL_MAX_FRAME_SIZE) != 0 ? "" : str15, (i10 & 32768) != 0 ? "" : str16, (i10 & DnsOverHttps.MAX_RESPONSE_SIZE) == 0 ? str17 : "", (i10 & 131072) != 0 ? 0L : j10);
    }

    public static /* synthetic */ LargeTradeItem copy$default(LargeTradeItem largeTradeItem, String str, String str2, String str3, String str4, String str5, String str6, String str7, String str8, String str9, String str10, String str11, String str12, String str13, String str14, String str15, String str16, String str17, long j10, int i10, Object obj) {
        long j11;
        String str18;
        String str19;
        String str20 = (i10 & 1) != 0 ? largeTradeItem.timestamp : str;
        String str21 = (i10 & 2) != 0 ? largeTradeItem.id : str2;
        String str22 = (i10 & 4) != 0 ? largeTradeItem.coin_type : str3;
        String str23 = (i10 & 8) != 0 ? largeTradeItem.trade_type : str4;
        String str24 = (i10 & 16) != 0 ? largeTradeItem.start_price : str5;
        String str25 = (i10 & 32) != 0 ? largeTradeItem.stop_price : str6;
        String str26 = (i10 & 64) != 0 ? largeTradeItem.max_price : str7;
        String str27 = (i10 & 128) != 0 ? largeTradeItem.max_price_usd : str8;
        String str28 = (i10 & 256) != 0 ? largeTradeItem.slippage_price : str9;
        String str29 = (i10 & 512) != 0 ? largeTradeItem.max_amount : str10;
        String str30 = (i10 & 1024) != 0 ? largeTradeItem.max_vol : str11;
        String str31 = (i10 & 2048) != 0 ? largeTradeItem.total_amount : str12;
        String str32 = (i10 & 4096) != 0 ? largeTradeItem.total_vol : str13;
        String str33 = (i10 & 8192) != 0 ? largeTradeItem.total_count : str14;
        String str34 = str20;
        String str35 = (i10 & Http2.INITIAL_MAX_FRAME_SIZE) != 0 ? largeTradeItem.total_turnover : str15;
        String str36 = (i10 & 32768) != 0 ? largeTradeItem.n : str16;
        String str37 = (i10 & DnsOverHttps.MAX_RESPONSE_SIZE) != 0 ? largeTradeItem.update_time : str17;
        if ((i10 & 131072) != 0) {
            str19 = str35;
            str18 = str37;
            j11 = largeTradeItem.draw_time;
        } else {
            j11 = j10;
            str18 = str37;
            str19 = str35;
        }
        return largeTradeItem.copy(str34, str21, str22, str23, str24, str25, str26, str27, str28, str29, str30, str31, str32, str33, str19, str36, str18, j11);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final String getTimestamp() {
        return this.timestamp;
    }

    /* JADX INFO: renamed from: component10, reason: from getter */
    public final String getMax_amount() {
        return this.max_amount;
    }

    /* JADX INFO: renamed from: component11, reason: from getter */
    public final String getMax_vol() {
        return this.max_vol;
    }

    /* JADX INFO: renamed from: component12, reason: from getter */
    public final String getTotal_amount() {
        return this.total_amount;
    }

    /* JADX INFO: renamed from: component13, reason: from getter */
    public final String getTotal_vol() {
        return this.total_vol;
    }

    /* JADX INFO: renamed from: component14, reason: from getter */
    public final String getTotal_count() {
        return this.total_count;
    }

    /* JADX INFO: renamed from: component15, reason: from getter */
    public final String getTotal_turnover() {
        return this.total_turnover;
    }

    /* JADX INFO: renamed from: component16, reason: from getter */
    public final String getN() {
        return this.n;
    }

    /* JADX INFO: renamed from: component17, reason: from getter */
    public final String getUpdate_time() {
        return this.update_time;
    }

    /* JADX INFO: renamed from: component18, reason: from getter */
    public final long getDraw_time() {
        return this.draw_time;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final String getId() {
        return this.id;
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    public final String getCoin_type() {
        return this.coin_type;
    }

    /* JADX INFO: renamed from: component4, reason: from getter */
    public final String getTrade_type() {
        return this.trade_type;
    }

    /* JADX INFO: renamed from: component5, reason: from getter */
    public final String getStart_price() {
        return this.start_price;
    }

    /* JADX INFO: renamed from: component6, reason: from getter */
    public final String getStop_price() {
        return this.stop_price;
    }

    /* JADX INFO: renamed from: component7, reason: from getter */
    public final String getMax_price() {
        return this.max_price;
    }

    /* JADX INFO: renamed from: component8, reason: from getter */
    public final String getMax_price_usd() {
        return this.max_price_usd;
    }

    /* JADX INFO: renamed from: component9, reason: from getter */
    public final String getSlippage_price() {
        return this.slippage_price;
    }

    public final LargeTradeItem copy(String timestamp, String id2, String coin_type, String trade_type, String start_price, String stop_price, String max_price, String max_price_usd, String slippage_price, String max_amount, String max_vol, String total_amount, String total_vol, String total_count, String total_turnover, String n10, String update_time, long draw_time) {
        return new LargeTradeItem(timestamp, id2, coin_type, trade_type, start_price, stop_price, max_price, max_price_usd, slippage_price, max_amount, max_vol, total_amount, total_vol, total_count, total_turnover, n10, update_time, draw_time);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof LargeTradeItem)) {
            return false;
        }
        LargeTradeItem largeTradeItem = (LargeTradeItem) other;
        return AbstractC7609s.f(this.timestamp, largeTradeItem.timestamp) && AbstractC7609s.f(this.id, largeTradeItem.id) && AbstractC7609s.f(this.coin_type, largeTradeItem.coin_type) && AbstractC7609s.f(this.trade_type, largeTradeItem.trade_type) && AbstractC7609s.f(this.start_price, largeTradeItem.start_price) && AbstractC7609s.f(this.stop_price, largeTradeItem.stop_price) && AbstractC7609s.f(this.max_price, largeTradeItem.max_price) && AbstractC7609s.f(this.max_price_usd, largeTradeItem.max_price_usd) && AbstractC7609s.f(this.slippage_price, largeTradeItem.slippage_price) && AbstractC7609s.f(this.max_amount, largeTradeItem.max_amount) && AbstractC7609s.f(this.max_vol, largeTradeItem.max_vol) && AbstractC7609s.f(this.total_amount, largeTradeItem.total_amount) && AbstractC7609s.f(this.total_vol, largeTradeItem.total_vol) && AbstractC7609s.f(this.total_count, largeTradeItem.total_count) && AbstractC7609s.f(this.total_turnover, largeTradeItem.total_turnover) && AbstractC7609s.f(this.n, largeTradeItem.n) && AbstractC7609s.f(this.update_time, largeTradeItem.update_time) && this.draw_time == largeTradeItem.draw_time;
    }

    public final String getCoin_type() {
        return this.coin_type;
    }

    public final long getDraw_time() {
        return this.draw_time;
    }

    public final String getId() {
        return this.id;
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

    public final String getN() {
        return this.n;
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

    public final String getTimestamp() {
        return this.timestamp;
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

    public int hashCode() {
        return Long.hashCode(this.draw_time) + d.a(this.update_time, d.a(this.n, d.a(this.total_turnover, d.a(this.total_count, d.a(this.total_vol, d.a(this.total_amount, d.a(this.max_vol, d.a(this.max_amount, d.a(this.slippage_price, d.a(this.max_price_usd, d.a(this.max_price, d.a(this.stop_price, d.a(this.start_price, d.a(this.trade_type, d.a(this.coin_type, d.a(this.id, this.timestamp.hashCode() * 31, 31), 31), 31), 31), 31), 31), 31), 31), 31), 31), 31), 31), 31), 31), 31), 31);
    }

    public final void setCoin_type(String str) {
        this.coin_type = str;
    }

    public final void setDraw_time(long j10) {
        this.draw_time = j10;
    }

    public final void setId(String str) {
        this.id = str;
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

    public final void setN(String str) {
        this.n = str;
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

    public final void setTimestamp(String str) {
        this.timestamp = str;
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

    public String toString() {
        return "LargeTradeItem(timestamp=" + this.timestamp + ", id=" + this.id + ", coin_type=" + this.coin_type + ", trade_type=" + this.trade_type + ", start_price=" + this.start_price + ", stop_price=" + this.stop_price + ", max_price=" + this.max_price + ", max_price_usd=" + this.max_price_usd + ", slippage_price=" + this.slippage_price + ", max_amount=" + this.max_amount + ", max_vol=" + this.max_vol + ", total_amount=" + this.total_amount + ", total_vol=" + this.total_vol + ", total_count=" + this.total_count + ", total_turnover=" + this.total_turnover + ", n=" + this.n + ", update_time=" + this.update_time + ", draw_time=" + this.draw_time + ')';
    }
}
