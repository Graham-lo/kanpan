package sp.aicoin_kline.chart.data;

import androidx.annotation.Keep;
import com.tencent.wcdb.database.SQLiteGlobal;
import com.umeng.analytics.pro.d;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import okhttp3.dnsoverhttps.DnsOverHttps;
import okhttp3.internal.http2.Http2;
import p167hg.AbstractC7609s;
import p398sh.aicoin.search.data.remote.SearchRemoteDataSource;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000\"\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000e\n\u0002\b`\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0002\b\u0002\b\u0087\b\u0018\u00002\u00020\u0001Bë\u0001\u0012\b\b\u0002\u0010\u0002\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0004\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0005\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0006\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0007\u001a\u00020\u0003\u0012\b\b\u0002\u0010\b\u001a\u00020\u0003\u0012\b\b\u0002\u0010\t\u001a\u00020\u0003\u0012\u0006\u0010\n\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u000b\u001a\u00020\u0003\u0012\b\b\u0002\u0010\f\u001a\u00020\u0003\u0012\b\b\u0002\u0010\r\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u000e\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u000f\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0010\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0011\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0012\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0013\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0014\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0015\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0016\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0017\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0018\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0019\u001a\u00020\u0003¢\u0006\u0004\b\u001a\u0010\u001bJ\t\u0010K\u001a\u00020\u0003HÆ\u0003J\t\u0010L\u001a\u00020\u0003HÆ\u0003J\t\u0010M\u001a\u00020\u0003HÆ\u0003J\t\u0010N\u001a\u00020\u0003HÆ\u0003J\t\u0010O\u001a\u00020\u0003HÆ\u0003J\t\u0010P\u001a\u00020\u0003HÆ\u0003J\t\u0010Q\u001a\u00020\u0003HÆ\u0003J\t\u0010R\u001a\u00020\u0003HÆ\u0003J\t\u0010S\u001a\u00020\u0003HÆ\u0003J\t\u0010T\u001a\u00020\u0003HÆ\u0003J\t\u0010U\u001a\u00020\u0003HÆ\u0003J\t\u0010V\u001a\u00020\u0003HÆ\u0003J\t\u0010W\u001a\u00020\u0003HÆ\u0003J\t\u0010X\u001a\u00020\u0003HÆ\u0003J\t\u0010Y\u001a\u00020\u0003HÆ\u0003J\t\u0010Z\u001a\u00020\u0003HÆ\u0003J\t\u0010[\u001a\u00020\u0003HÆ\u0003J\t\u0010\\\u001a\u00020\u0003HÆ\u0003J\t\u0010]\u001a\u00020\u0003HÆ\u0003J\t\u0010^\u001a\u00020\u0003HÆ\u0003J\t\u0010_\u001a\u00020\u0003HÆ\u0003J\t\u0010`\u001a\u00020\u0003HÆ\u0003J\t\u0010a\u001a\u00020\u0003HÆ\u0003Jï\u0001\u0010b\u001a\u00020\u00002\b\b\u0002\u0010\u0002\u001a\u00020\u00032\b\b\u0002\u0010\u0004\u001a\u00020\u00032\b\b\u0002\u0010\u0005\u001a\u00020\u00032\b\b\u0002\u0010\u0006\u001a\u00020\u00032\b\b\u0002\u0010\u0007\u001a\u00020\u00032\b\b\u0002\u0010\b\u001a\u00020\u00032\b\b\u0002\u0010\t\u001a\u00020\u00032\b\b\u0002\u0010\n\u001a\u00020\u00032\b\b\u0002\u0010\u000b\u001a\u00020\u00032\b\b\u0002\u0010\f\u001a\u00020\u00032\b\b\u0002\u0010\r\u001a\u00020\u00032\b\b\u0002\u0010\u000e\u001a\u00020\u00032\b\b\u0002\u0010\u000f\u001a\u00020\u00032\b\b\u0002\u0010\u0010\u001a\u00020\u00032\b\b\u0002\u0010\u0011\u001a\u00020\u00032\b\b\u0002\u0010\u0012\u001a\u00020\u00032\b\b\u0002\u0010\u0013\u001a\u00020\u00032\b\b\u0002\u0010\u0014\u001a\u00020\u00032\b\b\u0002\u0010\u0015\u001a\u00020\u00032\b\b\u0002\u0010\u0016\u001a\u00020\u00032\b\b\u0002\u0010\u0017\u001a\u00020\u00032\b\b\u0002\u0010\u0018\u001a\u00020\u00032\b\b\u0002\u0010\u0019\u001a\u00020\u0003HÆ\u0001J\u0013\u0010c\u001a\u00020d2\b\u0010e\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010f\u001a\u00020gHÖ\u0001J\t\u0010h\u001a\u00020\u0003HÖ\u0001R\u001a\u0010\u0002\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u001c\u0010\u001d\"\u0004\b\u001e\u0010\u001fR\u001a\u0010\u0004\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b \u0010\u001d\"\u0004\b!\u0010\u001fR\u001a\u0010\u0005\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\"\u0010\u001d\"\u0004\b#\u0010\u001fR\u001a\u0010\u0006\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b$\u0010\u001d\"\u0004\b%\u0010\u001fR\u001a\u0010\u0007\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b&\u0010\u001d\"\u0004\b'\u0010\u001fR\u001a\u0010\b\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b(\u0010\u001d\"\u0004\b)\u0010\u001fR\u001a\u0010\t\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b*\u0010\u001d\"\u0004\b+\u0010\u001fR\u0011\u0010\n\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b,\u0010\u001dR\u001a\u0010\u000b\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b-\u0010\u001d\"\u0004\b.\u0010\u001fR\u001a\u0010\f\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b/\u0010\u001d\"\u0004\b0\u0010\u001fR\u001a\u0010\r\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b1\u0010\u001d\"\u0004\b2\u0010\u001fR\u001a\u0010\u000e\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b3\u0010\u001d\"\u0004\b4\u0010\u001fR\u001a\u0010\u000f\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b5\u0010\u001d\"\u0004\b6\u0010\u001fR\u001a\u0010\u0010\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b7\u0010\u001d\"\u0004\b8\u0010\u001fR\u001a\u0010\u0011\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b9\u0010\u001d\"\u0004\b:\u0010\u001fR\u001a\u0010\u0012\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b;\u0010\u001d\"\u0004\b<\u0010\u001fR\u001a\u0010\u0013\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b=\u0010\u001d\"\u0004\b>\u0010\u001fR\u001a\u0010\u0014\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b?\u0010\u001d\"\u0004\b@\u0010\u001fR\u001a\u0010\u0015\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\bA\u0010\u001d\"\u0004\bB\u0010\u001fR\u001a\u0010\u0016\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\bC\u0010\u001d\"\u0004\bD\u0010\u001fR\u001a\u0010\u0017\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\bE\u0010\u001d\"\u0004\bF\u0010\u001fR\u001a\u0010\u0018\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\bG\u0010\u001d\"\u0004\bH\u0010\u001fR\u001a\u0010\u0019\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\bI\u0010\u001d\"\u0004\bJ\u0010\u001f¨\u0006i"}, d2 = {"Lsp/aicoin_kline/chart/data/LargeOrderInfo;", "", "x", "", "depth_state", "trade_type", "coin_type", "depth_type", "depth_price", "trade_amount", "trade_turnover", "depth_amount", "depth_turnover", "trade_rate", "trade_count", "high_trade_amount", "high_trade_turnover", "position_sub", "last_amount", "last_turnover", d.f89985p, "miss_time", "market_logo", SearchRemoteDataSource.HTTP_PARSE_KEY_ITEM_MARKET_NAME, "orderdownBound", "completedownBound", "<init>", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V", "getX", "()Ljava/lang/String;", "setX", "(Ljava/lang/String;)V", "getDepth_state", "setDepth_state", "getTrade_type", "setTrade_type", "getCoin_type", "setCoin_type", "getDepth_type", "setDepth_type", "getDepth_price", "setDepth_price", "getTrade_amount", "setTrade_amount", "getTrade_turnover", "getDepth_amount", "setDepth_amount", "getDepth_turnover", "setDepth_turnover", "getTrade_rate", "setTrade_rate", "getTrade_count", "setTrade_count", "getHigh_trade_amount", "setHigh_trade_amount", "getHigh_trade_turnover", "setHigh_trade_turnover", "getPosition_sub", "setPosition_sub", "getLast_amount", "setLast_amount", "getLast_turnover", "setLast_turnover", "getStart_time", "setStart_time", "getMiss_time", "setMiss_time", "getMarket_logo", "setMarket_logo", "getMarket_name", "setMarket_name", "getOrderdownBound", "setOrderdownBound", "getCompletedownBound", "setCompletedownBound", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "component9", "component10", "component11", "component12", "component13", "component14", "component15", "component16", "component17", "component18", "component19", "component20", "component21", "component22", "component23", "copy", "equals", "", "other", "hashCode", "", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class LargeOrderInfo {
    private String coin_type;
    private String completedownBound;
    private String depth_amount;
    private String depth_price;
    private String depth_state;
    private String depth_turnover;
    private String depth_type;
    private String high_trade_amount;
    private String high_trade_turnover;
    private String last_amount;
    private String last_turnover;
    private String market_logo;
    private String market_name;
    private String miss_time;
    private String orderdownBound;
    private String position_sub;
    private String start_time;
    private String trade_amount;
    private String trade_count;
    private String trade_rate;
    private final String trade_turnover;
    private String trade_type;
    private String x;

    public LargeOrderInfo(String str, String str2, String str3, String str4, String str5, String str6, String str7, String str8, String str9, String str10, String str11, String str12, String str13, String str14, String str15, String str16, String str17, String str18, String str19, String str20, String str21, String str22, String str23) {
        this.x = str;
        this.depth_state = str2;
        this.trade_type = str3;
        this.coin_type = str4;
        this.depth_type = str5;
        this.depth_price = str6;
        this.trade_amount = str7;
        this.trade_turnover = str8;
        this.depth_amount = str9;
        this.depth_turnover = str10;
        this.trade_rate = str11;
        this.trade_count = str12;
        this.high_trade_amount = str13;
        this.high_trade_turnover = str14;
        this.position_sub = str15;
        this.last_amount = str16;
        this.last_turnover = str17;
        this.start_time = str18;
        this.miss_time = str19;
        this.market_logo = str20;
        this.market_name = str21;
        this.orderdownBound = str22;
        this.completedownBound = str23;
    }

    public /* synthetic */ LargeOrderInfo(String str, String str2, String str3, String str4, String str5, String str6, String str7, String str8, String str9, String str10, String str11, String str12, String str13, String str14, String str15, String str16, String str17, String str18, String str19, String str20, String str21, String str22, String str23, int i10, DefaultConstructorMarker defaultConstructorMarker) {
        this((i10 & 1) != 0 ? "0" : str, (i10 & 2) != 0 ? "0" : str2, (i10 & 4) != 0 ? "" : str3, (i10 & 8) != 0 ? "" : str4, (i10 & 16) != 0 ? "" : str5, (i10 & 32) != 0 ? "0" : str6, (i10 & 64) != 0 ? "0" : str7, str8, (i10 & 256) != 0 ? "0" : str9, (i10 & 512) != 0 ? "0" : str10, (i10 & 1024) != 0 ? "0" : str11, (i10 & 2048) != 0 ? "0" : str12, (i10 & 4096) != 0 ? "0" : str13, (i10 & 8192) != 0 ? "0" : str14, (i10 & Http2.INITIAL_MAX_FRAME_SIZE) != 0 ? "0" : str15, (32768 & i10) != 0 ? "0" : str16, (65536 & i10) != 0 ? "0" : str17, (131072 & i10) != 0 ? "0" : str18, (262144 & i10) != 0 ? "0" : str19, (524288 & i10) != 0 ? "" : str20, (1048576 & i10) != 0 ? "" : str21, (2097152 & i10) != 0 ? "" : str22, (i10 & 4194304) != 0 ? "" : str23);
    }

    public static /* synthetic */ LargeOrderInfo copy$default(LargeOrderInfo largeOrderInfo, String str, String str2, String str3, String str4, String str5, String str6, String str7, String str8, String str9, String str10, String str11, String str12, String str13, String str14, String str15, String str16, String str17, String str18, String str19, String str20, String str21, String str22, String str23, int i10, Object obj) {
        String str24;
        String str25;
        String str26 = (i10 & 1) != 0 ? largeOrderInfo.x : str;
        String str27 = (i10 & 2) != 0 ? largeOrderInfo.depth_state : str2;
        String str28 = (i10 & 4) != 0 ? largeOrderInfo.trade_type : str3;
        String str29 = (i10 & 8) != 0 ? largeOrderInfo.coin_type : str4;
        String str30 = (i10 & 16) != 0 ? largeOrderInfo.depth_type : str5;
        String str31 = (i10 & 32) != 0 ? largeOrderInfo.depth_price : str6;
        String str32 = (i10 & 64) != 0 ? largeOrderInfo.trade_amount : str7;
        String str33 = (i10 & 128) != 0 ? largeOrderInfo.trade_turnover : str8;
        String str34 = (i10 & 256) != 0 ? largeOrderInfo.depth_amount : str9;
        String str35 = (i10 & 512) != 0 ? largeOrderInfo.depth_turnover : str10;
        String str36 = (i10 & 1024) != 0 ? largeOrderInfo.trade_rate : str11;
        String str37 = (i10 & 2048) != 0 ? largeOrderInfo.trade_count : str12;
        String str38 = (i10 & 4096) != 0 ? largeOrderInfo.high_trade_amount : str13;
        String str39 = (i10 & 8192) != 0 ? largeOrderInfo.high_trade_turnover : str14;
        String str40 = str26;
        String str41 = (i10 & Http2.INITIAL_MAX_FRAME_SIZE) != 0 ? largeOrderInfo.position_sub : str15;
        String str42 = (i10 & 32768) != 0 ? largeOrderInfo.last_amount : str16;
        String str43 = (i10 & DnsOverHttps.MAX_RESPONSE_SIZE) != 0 ? largeOrderInfo.last_turnover : str17;
        String str44 = (i10 & 131072) != 0 ? largeOrderInfo.start_time : str18;
        String str45 = (i10 & 262144) != 0 ? largeOrderInfo.miss_time : str19;
        String str46 = (i10 & SQLiteGlobal.journalSizeLimit) != 0 ? largeOrderInfo.market_logo : str20;
        String str47 = (i10 & 1048576) != 0 ? largeOrderInfo.market_name : str21;
        String str48 = (i10 & 2097152) != 0 ? largeOrderInfo.orderdownBound : str22;
        if ((i10 & 4194304) != 0) {
            str25 = str48;
            str24 = largeOrderInfo.completedownBound;
        } else {
            str24 = str23;
            str25 = str48;
        }
        return largeOrderInfo.copy(str40, str27, str28, str29, str30, str31, str32, str33, str34, str35, str36, str37, str38, str39, str41, str42, str43, str44, str45, str46, str47, str25, str24);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final String getX() {
        return this.x;
    }

    /* JADX INFO: renamed from: component10, reason: from getter */
    public final String getDepth_turnover() {
        return this.depth_turnover;
    }

    /* JADX INFO: renamed from: component11, reason: from getter */
    public final String getTrade_rate() {
        return this.trade_rate;
    }

    /* JADX INFO: renamed from: component12, reason: from getter */
    public final String getTrade_count() {
        return this.trade_count;
    }

    /* JADX INFO: renamed from: component13, reason: from getter */
    public final String getHigh_trade_amount() {
        return this.high_trade_amount;
    }

    /* JADX INFO: renamed from: component14, reason: from getter */
    public final String getHigh_trade_turnover() {
        return this.high_trade_turnover;
    }

    /* JADX INFO: renamed from: component15, reason: from getter */
    public final String getPosition_sub() {
        return this.position_sub;
    }

    /* JADX INFO: renamed from: component16, reason: from getter */
    public final String getLast_amount() {
        return this.last_amount;
    }

    /* JADX INFO: renamed from: component17, reason: from getter */
    public final String getLast_turnover() {
        return this.last_turnover;
    }

    /* JADX INFO: renamed from: component18, reason: from getter */
    public final String getStart_time() {
        return this.start_time;
    }

    /* JADX INFO: renamed from: component19, reason: from getter */
    public final String getMiss_time() {
        return this.miss_time;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final String getDepth_state() {
        return this.depth_state;
    }

    /* JADX INFO: renamed from: component20, reason: from getter */
    public final String getMarket_logo() {
        return this.market_logo;
    }

    /* JADX INFO: renamed from: component21, reason: from getter */
    public final String getMarket_name() {
        return this.market_name;
    }

    /* JADX INFO: renamed from: component22, reason: from getter */
    public final String getOrderdownBound() {
        return this.orderdownBound;
    }

    /* JADX INFO: renamed from: component23, reason: from getter */
    public final String getCompletedownBound() {
        return this.completedownBound;
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    public final String getTrade_type() {
        return this.trade_type;
    }

    /* JADX INFO: renamed from: component4, reason: from getter */
    public final String getCoin_type() {
        return this.coin_type;
    }

    /* JADX INFO: renamed from: component5, reason: from getter */
    public final String getDepth_type() {
        return this.depth_type;
    }

    /* JADX INFO: renamed from: component6, reason: from getter */
    public final String getDepth_price() {
        return this.depth_price;
    }

    /* JADX INFO: renamed from: component7, reason: from getter */
    public final String getTrade_amount() {
        return this.trade_amount;
    }

    /* JADX INFO: renamed from: component8, reason: from getter */
    public final String getTrade_turnover() {
        return this.trade_turnover;
    }

    /* JADX INFO: renamed from: component9, reason: from getter */
    public final String getDepth_amount() {
        return this.depth_amount;
    }

    public final LargeOrderInfo copy(String x10, String depth_state, String trade_type, String coin_type, String depth_type, String depth_price, String trade_amount, String trade_turnover, String depth_amount, String depth_turnover, String trade_rate, String trade_count, String high_trade_amount, String high_trade_turnover, String position_sub, String last_amount, String last_turnover, String start_time, String miss_time, String market_logo, String market_name, String orderdownBound, String completedownBound) {
        return new LargeOrderInfo(x10, depth_state, trade_type, coin_type, depth_type, depth_price, trade_amount, trade_turnover, depth_amount, depth_turnover, trade_rate, trade_count, high_trade_amount, high_trade_turnover, position_sub, last_amount, last_turnover, start_time, miss_time, market_logo, market_name, orderdownBound, completedownBound);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof LargeOrderInfo)) {
            return false;
        }
        LargeOrderInfo largeOrderInfo = (LargeOrderInfo) other;
        return AbstractC7609s.f(this.x, largeOrderInfo.x) && AbstractC7609s.f(this.depth_state, largeOrderInfo.depth_state) && AbstractC7609s.f(this.trade_type, largeOrderInfo.trade_type) && AbstractC7609s.f(this.coin_type, largeOrderInfo.coin_type) && AbstractC7609s.f(this.depth_type, largeOrderInfo.depth_type) && AbstractC7609s.f(this.depth_price, largeOrderInfo.depth_price) && AbstractC7609s.f(this.trade_amount, largeOrderInfo.trade_amount) && AbstractC7609s.f(this.trade_turnover, largeOrderInfo.trade_turnover) && AbstractC7609s.f(this.depth_amount, largeOrderInfo.depth_amount) && AbstractC7609s.f(this.depth_turnover, largeOrderInfo.depth_turnover) && AbstractC7609s.f(this.trade_rate, largeOrderInfo.trade_rate) && AbstractC7609s.f(this.trade_count, largeOrderInfo.trade_count) && AbstractC7609s.f(this.high_trade_amount, largeOrderInfo.high_trade_amount) && AbstractC7609s.f(this.high_trade_turnover, largeOrderInfo.high_trade_turnover) && AbstractC7609s.f(this.position_sub, largeOrderInfo.position_sub) && AbstractC7609s.f(this.last_amount, largeOrderInfo.last_amount) && AbstractC7609s.f(this.last_turnover, largeOrderInfo.last_turnover) && AbstractC7609s.f(this.start_time, largeOrderInfo.start_time) && AbstractC7609s.f(this.miss_time, largeOrderInfo.miss_time) && AbstractC7609s.f(this.market_logo, largeOrderInfo.market_logo) && AbstractC7609s.f(this.market_name, largeOrderInfo.market_name) && AbstractC7609s.f(this.orderdownBound, largeOrderInfo.orderdownBound) && AbstractC7609s.f(this.completedownBound, largeOrderInfo.completedownBound);
    }

    public final String getCoin_type() {
        return this.coin_type;
    }

    public final String getCompletedownBound() {
        return this.completedownBound;
    }

    public final String getDepth_amount() {
        return this.depth_amount;
    }

    public final String getDepth_price() {
        return this.depth_price;
    }

    public final String getDepth_state() {
        return this.depth_state;
    }

    public final String getDepth_turnover() {
        return this.depth_turnover;
    }

    public final String getDepth_type() {
        return this.depth_type;
    }

    public final String getHigh_trade_amount() {
        return this.high_trade_amount;
    }

    public final String getHigh_trade_turnover() {
        return this.high_trade_turnover;
    }

    public final String getLast_amount() {
        return this.last_amount;
    }

    public final String getLast_turnover() {
        return this.last_turnover;
    }

    public final String getMarket_logo() {
        return this.market_logo;
    }

    public final String getMarket_name() {
        return this.market_name;
    }

    public final String getMiss_time() {
        return this.miss_time;
    }

    public final String getOrderdownBound() {
        return this.orderdownBound;
    }

    public final String getPosition_sub() {
        return this.position_sub;
    }

    public final String getStart_time() {
        return this.start_time;
    }

    public final String getTrade_amount() {
        return this.trade_amount;
    }

    public final String getTrade_count() {
        return this.trade_count;
    }

    public final String getTrade_rate() {
        return this.trade_rate;
    }

    public final String getTrade_turnover() {
        return this.trade_turnover;
    }

    public final String getTrade_type() {
        return this.trade_type;
    }

    public final String getX() {
        return this.x;
    }

    public int hashCode() {
        return this.completedownBound.hashCode() + kk.d.a(this.orderdownBound, kk.d.a(this.market_name, kk.d.a(this.market_logo, kk.d.a(this.miss_time, kk.d.a(this.start_time, kk.d.a(this.last_turnover, kk.d.a(this.last_amount, kk.d.a(this.position_sub, kk.d.a(this.high_trade_turnover, kk.d.a(this.high_trade_amount, kk.d.a(this.trade_count, kk.d.a(this.trade_rate, kk.d.a(this.depth_turnover, kk.d.a(this.depth_amount, kk.d.a(this.trade_turnover, kk.d.a(this.trade_amount, kk.d.a(this.depth_price, kk.d.a(this.depth_type, kk.d.a(this.coin_type, kk.d.a(this.trade_type, kk.d.a(this.depth_state, this.x.hashCode() * 31, 31), 31), 31), 31), 31), 31), 31), 31), 31), 31), 31), 31), 31), 31), 31), 31), 31), 31), 31), 31), 31);
    }

    public final void setCoin_type(String str) {
        this.coin_type = str;
    }

    public final void setCompletedownBound(String str) {
        this.completedownBound = str;
    }

    public final void setDepth_amount(String str) {
        this.depth_amount = str;
    }

    public final void setDepth_price(String str) {
        this.depth_price = str;
    }

    public final void setDepth_state(String str) {
        this.depth_state = str;
    }

    public final void setDepth_turnover(String str) {
        this.depth_turnover = str;
    }

    public final void setDepth_type(String str) {
        this.depth_type = str;
    }

    public final void setHigh_trade_amount(String str) {
        this.high_trade_amount = str;
    }

    public final void setHigh_trade_turnover(String str) {
        this.high_trade_turnover = str;
    }

    public final void setLast_amount(String str) {
        this.last_amount = str;
    }

    public final void setLast_turnover(String str) {
        this.last_turnover = str;
    }

    public final void setMarket_logo(String str) {
        this.market_logo = str;
    }

    public final void setMarket_name(String str) {
        this.market_name = str;
    }

    public final void setMiss_time(String str) {
        this.miss_time = str;
    }

    public final void setOrderdownBound(String str) {
        this.orderdownBound = str;
    }

    public final void setPosition_sub(String str) {
        this.position_sub = str;
    }

    public final void setStart_time(String str) {
        this.start_time = str;
    }

    public final void setTrade_amount(String str) {
        this.trade_amount = str;
    }

    public final void setTrade_count(String str) {
        this.trade_count = str;
    }

    public final void setTrade_rate(String str) {
        this.trade_rate = str;
    }

    public final void setTrade_type(String str) {
        this.trade_type = str;
    }

    public final void setX(String str) {
        this.x = str;
    }

    public String toString() {
        return "LargeOrderInfo(x=" + this.x + ", depth_state=" + this.depth_state + ", trade_type=" + this.trade_type + ", coin_type=" + this.coin_type + ", depth_type=" + this.depth_type + ", depth_price=" + this.depth_price + ", trade_amount=" + this.trade_amount + ", trade_turnover=" + this.trade_turnover + ", depth_amount=" + this.depth_amount + ", depth_turnover=" + this.depth_turnover + ", trade_rate=" + this.trade_rate + ", trade_count=" + this.trade_count + ", high_trade_amount=" + this.high_trade_amount + ", high_trade_turnover=" + this.high_trade_turnover + ", position_sub=" + this.position_sub + ", last_amount=" + this.last_amount + ", last_turnover=" + this.last_turnover + ", start_time=" + this.start_time + ", miss_time=" + this.miss_time + ", market_logo=" + this.market_logo + ", market_name=" + this.market_name + ", orderdownBound=" + this.orderdownBound + ", completedownBound=" + this.completedownBound + ')';
    }
}
