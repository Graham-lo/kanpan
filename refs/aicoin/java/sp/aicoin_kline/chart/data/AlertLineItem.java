package sp.aicoin_kline.chart.data;

import androidx.annotation.Keep;
import com.tencent.wcdb.database.SQLiteDatabase;
import com.tencent.wcdb.database.SQLiteGlobal;
import com.umeng.analytics.pro.d;
import kotlin.Metadata;
import okhttp3.dnsoverhttps.DnsOverHttps;
import okhttp3.internal.http2.Http2;
import okhttp3.internal.http2.Http2Connection;
import p167hg.AbstractC7609s;
import p398sh.aicoin.search.data.remote.SearchRemoteDataSource;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000\"\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0005\n\u0002\u0010\b\n\u0002\bn\n\u0002\u0010\u000b\n\u0002\b\u0004\b\u0087\b\u0018\u00002\u00020\u0001Bå\u0002\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0005\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0006\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0007\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\b\u001a\u0004\u0018\u00010\t\u0012\b\u0010\n\u001a\u0004\u0018\u00010\t\u0012\b\u0010\u000b\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\f\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\r\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u000e\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u000f\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0010\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0011\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0012\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0013\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0014\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0015\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0016\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0017\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0018\u001a\u0004\u0018\u00010\t\u0012\b\u0010\u0019\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u001a\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u001b\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u001c\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u001d\u001a\u0004\u0018\u00010\t\u0012\b\u0010\u001e\u001a\u0004\u0018\u00010\t\u0012\b\u0010\u001f\u001a\u0004\u0018\u00010\t\u0012\b\u0010 \u001a\u0004\u0018\u00010\u0003\u0012\b\u0010!\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\"\u001a\u0004\u0018\u00010\t\u0012\b\u0010#\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010$\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010%\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010&\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b'\u0010(J\u000b\u0010R\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010S\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010T\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010U\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010V\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0010\u0010W\u001a\u0004\u0018\u00010\tHÆ\u0003¢\u0006\u0002\u00100J\u0010\u0010X\u001a\u0004\u0018\u00010\tHÆ\u0003¢\u0006\u0002\u00100J\u000b\u0010Y\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010Z\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010[\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\\\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010]\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010^\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010_\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010`\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010a\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010b\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010c\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010d\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010e\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0010\u0010f\u001a\u0004\u0018\u00010\tHÆ\u0003¢\u0006\u0002\u00100J\u000b\u0010g\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010h\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010i\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010j\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0010\u0010k\u001a\u0004\u0018\u00010\tHÆ\u0003¢\u0006\u0002\u00100J\u0010\u0010l\u001a\u0004\u0018\u00010\tHÆ\u0003¢\u0006\u0002\u00100J\u0010\u0010m\u001a\u0004\u0018\u00010\tHÆ\u0003¢\u0006\u0002\u00100J\u000b\u0010n\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010o\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0010\u0010p\u001a\u0004\u0018\u00010\tHÆ\u0003¢\u0006\u0002\u00100J\u000b\u0010q\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010r\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010s\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010t\u001a\u0004\u0018\u00010\u0003HÆ\u0003J²\u0003\u0010u\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0005\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\t2\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\t2\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u000e\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u000f\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0010\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0011\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0012\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0013\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0014\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0015\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0016\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0017\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0018\u001a\u0004\u0018\u00010\t2\n\b\u0002\u0010\u0019\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u001a\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u001b\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u001c\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u001d\u001a\u0004\u0018\u00010\t2\n\b\u0002\u0010\u001e\u001a\u0004\u0018\u00010\t2\n\b\u0002\u0010\u001f\u001a\u0004\u0018\u00010\t2\n\b\u0002\u0010 \u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010!\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\"\u001a\u0004\u0018\u00010\t2\n\b\u0002\u0010#\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010$\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010%\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010&\u001a\u0004\u0018\u00010\u0003HÆ\u0001¢\u0006\u0002\u0010vJ\u0013\u0010w\u001a\u00020x2\b\u0010y\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010z\u001a\u00020\tHÖ\u0001J\t\u0010{\u001a\u00020\u0003HÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b)\u0010*R\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b+\u0010*R\u0013\u0010\u0005\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b,\u0010*R\u0013\u0010\u0006\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b-\u0010*R\u0013\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b.\u0010*R\u0015\u0010\b\u001a\u0004\u0018\u00010\t¢\u0006\n\n\u0002\u00101\u001a\u0004\b/\u00100R\u0015\u0010\n\u001a\u0004\u0018\u00010\t¢\u0006\n\n\u0002\u00101\u001a\u0004\b2\u00100R\u0013\u0010\u000b\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b3\u0010*R\u0013\u0010\f\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b4\u0010*R\u0013\u0010\r\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b5\u0010*R\u0013\u0010\u000e\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b6\u0010*R\u0013\u0010\u000f\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b7\u0010*R\u0013\u0010\u0010\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b8\u0010*R\u0013\u0010\u0011\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b9\u0010*R\u0013\u0010\u0012\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b:\u0010*R\u0013\u0010\u0013\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b;\u0010*R\u0013\u0010\u0014\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b<\u0010*R\u0013\u0010\u0015\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b=\u0010*R\u0013\u0010\u0016\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b>\u0010*R\u0013\u0010\u0017\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b?\u0010*R\u0015\u0010\u0018\u001a\u0004\u0018\u00010\t¢\u0006\n\n\u0002\u00101\u001a\u0004\b@\u00100R\u0013\u0010\u0019\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\bA\u0010*R\u0013\u0010\u001a\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\bB\u0010*R\u0013\u0010\u001b\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\bC\u0010*R\u0013\u0010\u001c\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\bD\u0010*R\u0015\u0010\u001d\u001a\u0004\u0018\u00010\t¢\u0006\n\n\u0002\u00101\u001a\u0004\b\u001d\u00100R\u0015\u0010\u001e\u001a\u0004\u0018\u00010\t¢\u0006\n\n\u0002\u00101\u001a\u0004\b\u001e\u00100R\u0015\u0010\u001f\u001a\u0004\u0018\u00010\t¢\u0006\n\n\u0002\u00101\u001a\u0004\b\u001f\u00100R\u0013\u0010 \u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\bE\u0010*R\u0013\u0010!\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\bF\u0010*R\u001e\u0010\"\u001a\u0004\u0018\u00010\tX\u0086\u000e¢\u0006\u0010\n\u0002\u00101\u001a\u0004\b\"\u00100\"\u0004\bG\u0010HR\u001c\u0010#\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\bI\u0010*\"\u0004\bJ\u0010KR\u001c\u0010$\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\bL\u0010*\"\u0004\bM\u0010KR\u001c\u0010%\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\bN\u0010*\"\u0004\bO\u0010KR\u001c\u0010&\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\bP\u0010*\"\u0004\bQ\u0010K¨\u0006|"}, d2 = {"Lsp/aicoin_kline/chart/data/AlertLineItem;", "", "id", "", "db_key", SearchRemoteDataSource.HTTP_PARSE_KEY_ITEM_COIN_NAME, "db_key_cmp", "show_cmp", "style", "", "mode", "frequency", "frequency_name", "set_price", "set_price_cmp", "mode_info", "mode_info_cmp", "created_at", "ews_time", "expend", "ews_price", "ews_price_cmp", "ews_type", "price_type", "voice_state", "currency_str", "symbol", "curr_prefix", "remarks", "is_pc", "is_app", "is_webhook", "webhook_url", d.f89986q, "isSelect", "preset_order_params", "orderAmount", "orderType", "orderUnit", "<init>", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V", "getId", "()Ljava/lang/String;", "getDb_key", "getShow", "getDb_key_cmp", "getShow_cmp", "getStyle", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getMode", "getFrequency", "getFrequency_name", "getSet_price", "getSet_price_cmp", "getMode_info", "getMode_info_cmp", "getCreated_at", "getEws_time", "getExpend", "getEws_price", "getEws_price_cmp", "getEws_type", "getPrice_type", "getVoice_state", "getCurrency_str", "getSymbol", "getCurr_prefix", "getRemarks", "getWebhook_url", "getEnd_time", "setSelect", "(Ljava/lang/Integer;)V", "getPreset_order_params", "setPreset_order_params", "(Ljava/lang/String;)V", "getOrderAmount", "setOrderAmount", "getOrderType", "setOrderType", "getOrderUnit", "setOrderUnit", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "component9", "component10", "component11", "component12", "component13", "component14", "component15", "component16", "component17", "component18", "component19", "component20", "component21", "component22", "component23", "component24", "component25", "component26", "component27", "component28", "component29", "component30", "component31", "component32", "component33", "component34", "component35", "copy", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Lsp/aicoin_kline/chart/data/AlertLineItem;", "equals", "", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class AlertLineItem {
    private final String created_at;
    private final String curr_prefix;
    private final String currency_str;
    private final String db_key;
    private final String db_key_cmp;
    private final String end_time;
    private final String ews_price;
    private final String ews_price_cmp;
    private final String ews_time;
    private final String ews_type;
    private final String expend;
    private final String frequency;
    private final String frequency_name;
    private final String id;
    private Integer isSelect;
    private final Integer is_app;
    private final Integer is_pc;
    private final Integer is_webhook;
    private final Integer mode;
    private final String mode_info;
    private final String mode_info_cmp;
    private String orderAmount;
    private String orderType;
    private String orderUnit;
    private String preset_order_params;
    private final String price_type;
    private final String remarks;
    private final String set_price;
    private final String set_price_cmp;
    private final String show;
    private final String show_cmp;
    private final Integer style;
    private final String symbol;
    private final Integer voice_state;
    private final String webhook_url;

    public AlertLineItem(String str, String str2, String str3, String str4, String str5, Integer num, Integer num2, String str6, String str7, String str8, String str9, String str10, String str11, String str12, String str13, String str14, String str15, String str16, String str17, String str18, Integer num3, String str19, String str20, String str21, String str22, Integer num4, Integer num5, Integer num6, String str23, String str24, Integer num7, String str25, String str26, String str27, String str28) {
        this.id = str;
        this.db_key = str2;
        this.show = str3;
        this.db_key_cmp = str4;
        this.show_cmp = str5;
        this.style = num;
        this.mode = num2;
        this.frequency = str6;
        this.frequency_name = str7;
        this.set_price = str8;
        this.set_price_cmp = str9;
        this.mode_info = str10;
        this.mode_info_cmp = str11;
        this.created_at = str12;
        this.ews_time = str13;
        this.expend = str14;
        this.ews_price = str15;
        this.ews_price_cmp = str16;
        this.ews_type = str17;
        this.price_type = str18;
        this.voice_state = num3;
        this.currency_str = str19;
        this.symbol = str20;
        this.curr_prefix = str21;
        this.remarks = str22;
        this.is_pc = num4;
        this.is_app = num5;
        this.is_webhook = num6;
        this.webhook_url = str23;
        this.end_time = str24;
        this.isSelect = num7;
        this.preset_order_params = str25;
        this.orderAmount = str26;
        this.orderType = str27;
        this.orderUnit = str28;
    }

    public static /* synthetic */ AlertLineItem copy$default(AlertLineItem alertLineItem, String str, String str2, String str3, String str4, String str5, Integer num, Integer num2, String str6, String str7, String str8, String str9, String str10, String str11, String str12, String str13, String str14, String str15, String str16, String str17, String str18, Integer num3, String str19, String str20, String str21, String str22, Integer num4, Integer num5, Integer num6, String str23, String str24, Integer num7, String str25, String str26, String str27, String str28, int i10, int i11, Object obj) {
        String str29;
        String str30;
        String str31 = (i10 & 1) != 0 ? alertLineItem.id : str;
        String str32 = (i10 & 2) != 0 ? alertLineItem.db_key : str2;
        String str33 = (i10 & 4) != 0 ? alertLineItem.show : str3;
        String str34 = (i10 & 8) != 0 ? alertLineItem.db_key_cmp : str4;
        String str35 = (i10 & 16) != 0 ? alertLineItem.show_cmp : str5;
        Integer num8 = (i10 & 32) != 0 ? alertLineItem.style : num;
        Integer num9 = (i10 & 64) != 0 ? alertLineItem.mode : num2;
        String str36 = (i10 & 128) != 0 ? alertLineItem.frequency : str6;
        String str37 = (i10 & 256) != 0 ? alertLineItem.frequency_name : str7;
        String str38 = (i10 & 512) != 0 ? alertLineItem.set_price : str8;
        String str39 = (i10 & 1024) != 0 ? alertLineItem.set_price_cmp : str9;
        String str40 = (i10 & 2048) != 0 ? alertLineItem.mode_info : str10;
        String str41 = (i10 & 4096) != 0 ? alertLineItem.mode_info_cmp : str11;
        String str42 = (i10 & 8192) != 0 ? alertLineItem.created_at : str12;
        String str43 = str31;
        String str44 = (i10 & Http2.INITIAL_MAX_FRAME_SIZE) != 0 ? alertLineItem.ews_time : str13;
        String str45 = (i10 & 32768) != 0 ? alertLineItem.expend : str14;
        String str46 = (i10 & DnsOverHttps.MAX_RESPONSE_SIZE) != 0 ? alertLineItem.ews_price : str15;
        String str47 = (i10 & 131072) != 0 ? alertLineItem.ews_price_cmp : str16;
        String str48 = (i10 & 262144) != 0 ? alertLineItem.ews_type : str17;
        String str49 = (i10 & SQLiteGlobal.journalSizeLimit) != 0 ? alertLineItem.price_type : str18;
        Integer num10 = (i10 & 1048576) != 0 ? alertLineItem.voice_state : num3;
        String str50 = (i10 & 2097152) != 0 ? alertLineItem.currency_str : str19;
        String str51 = (i10 & 4194304) != 0 ? alertLineItem.symbol : str20;
        String str52 = (i10 & 8388608) != 0 ? alertLineItem.curr_prefix : str21;
        String str53 = (i10 & Http2Connection.OKHTTP_CLIENT_WINDOW_SIZE) != 0 ? alertLineItem.remarks : str22;
        Integer num11 = (i10 & 33554432) != 0 ? alertLineItem.is_pc : num4;
        Integer num12 = (i10 & 67108864) != 0 ? alertLineItem.is_app : num5;
        Integer num13 = (i10 & 134217728) != 0 ? alertLineItem.is_webhook : num6;
        String str54 = (i10 & 268435456) != 0 ? alertLineItem.webhook_url : str23;
        String str55 = (i10 & SQLiteDatabase.ENABLE_WRITE_AHEAD_LOGGING) != 0 ? alertLineItem.end_time : str24;
        Integer num14 = (i10 & 1073741824) != 0 ? alertLineItem.isSelect : num7;
        String str56 = (i10 & Integer.MIN_VALUE) != 0 ? alertLineItem.preset_order_params : str25;
        String str57 = (i11 & 1) != 0 ? alertLineItem.orderAmount : str26;
        String str58 = (i11 & 2) != 0 ? alertLineItem.orderType : str27;
        if ((i11 & 4) != 0) {
            str30 = str58;
            str29 = alertLineItem.orderUnit;
        } else {
            str29 = str28;
            str30 = str58;
        }
        return alertLineItem.copy(str43, str32, str33, str34, str35, num8, num9, str36, str37, str38, str39, str40, str41, str42, str44, str45, str46, str47, str48, str49, num10, str50, str51, str52, str53, num11, num12, num13, str54, str55, num14, str56, str57, str30, str29);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final String getId() {
        return this.id;
    }

    /* JADX INFO: renamed from: component10, reason: from getter */
    public final String getSet_price() {
        return this.set_price;
    }

    /* JADX INFO: renamed from: component11, reason: from getter */
    public final String getSet_price_cmp() {
        return this.set_price_cmp;
    }

    /* JADX INFO: renamed from: component12, reason: from getter */
    public final String getMode_info() {
        return this.mode_info;
    }

    /* JADX INFO: renamed from: component13, reason: from getter */
    public final String getMode_info_cmp() {
        return this.mode_info_cmp;
    }

    /* JADX INFO: renamed from: component14, reason: from getter */
    public final String getCreated_at() {
        return this.created_at;
    }

    /* JADX INFO: renamed from: component15, reason: from getter */
    public final String getEws_time() {
        return this.ews_time;
    }

    /* JADX INFO: renamed from: component16, reason: from getter */
    public final String getExpend() {
        return this.expend;
    }

    /* JADX INFO: renamed from: component17, reason: from getter */
    public final String getEws_price() {
        return this.ews_price;
    }

    /* JADX INFO: renamed from: component18, reason: from getter */
    public final String getEws_price_cmp() {
        return this.ews_price_cmp;
    }

    /* JADX INFO: renamed from: component19, reason: from getter */
    public final String getEws_type() {
        return this.ews_type;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final String getDb_key() {
        return this.db_key;
    }

    /* JADX INFO: renamed from: component20, reason: from getter */
    public final String getPrice_type() {
        return this.price_type;
    }

    /* JADX INFO: renamed from: component21, reason: from getter */
    public final Integer getVoice_state() {
        return this.voice_state;
    }

    /* JADX INFO: renamed from: component22, reason: from getter */
    public final String getCurrency_str() {
        return this.currency_str;
    }

    /* JADX INFO: renamed from: component23, reason: from getter */
    public final String getSymbol() {
        return this.symbol;
    }

    /* JADX INFO: renamed from: component24, reason: from getter */
    public final String getCurr_prefix() {
        return this.curr_prefix;
    }

    /* JADX INFO: renamed from: component25, reason: from getter */
    public final String getRemarks() {
        return this.remarks;
    }

    /* JADX INFO: renamed from: component26, reason: from getter */
    public final Integer getIs_pc() {
        return this.is_pc;
    }

    /* JADX INFO: renamed from: component27, reason: from getter */
    public final Integer getIs_app() {
        return this.is_app;
    }

    /* JADX INFO: renamed from: component28, reason: from getter */
    public final Integer getIs_webhook() {
        return this.is_webhook;
    }

    /* JADX INFO: renamed from: component29, reason: from getter */
    public final String getWebhook_url() {
        return this.webhook_url;
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    public final String getShow() {
        return this.show;
    }

    /* JADX INFO: renamed from: component30, reason: from getter */
    public final String getEnd_time() {
        return this.end_time;
    }

    /* JADX INFO: renamed from: component31, reason: from getter */
    public final Integer getIsSelect() {
        return this.isSelect;
    }

    /* JADX INFO: renamed from: component32, reason: from getter */
    public final String getPreset_order_params() {
        return this.preset_order_params;
    }

    /* JADX INFO: renamed from: component33, reason: from getter */
    public final String getOrderAmount() {
        return this.orderAmount;
    }

    /* JADX INFO: renamed from: component34, reason: from getter */
    public final String getOrderType() {
        return this.orderType;
    }

    /* JADX INFO: renamed from: component35, reason: from getter */
    public final String getOrderUnit() {
        return this.orderUnit;
    }

    /* JADX INFO: renamed from: component4, reason: from getter */
    public final String getDb_key_cmp() {
        return this.db_key_cmp;
    }

    /* JADX INFO: renamed from: component5, reason: from getter */
    public final String getShow_cmp() {
        return this.show_cmp;
    }

    /* JADX INFO: renamed from: component6, reason: from getter */
    public final Integer getStyle() {
        return this.style;
    }

    /* JADX INFO: renamed from: component7, reason: from getter */
    public final Integer getMode() {
        return this.mode;
    }

    /* JADX INFO: renamed from: component8, reason: from getter */
    public final String getFrequency() {
        return this.frequency;
    }

    /* JADX INFO: renamed from: component9, reason: from getter */
    public final String getFrequency_name() {
        return this.frequency_name;
    }

    public final AlertLineItem copy(String id2, String db_key, String show, String db_key_cmp, String show_cmp, Integer style, Integer mode, String frequency, String frequency_name, String set_price, String set_price_cmp, String mode_info, String mode_info_cmp, String created_at, String ews_time, String expend, String ews_price, String ews_price_cmp, String ews_type, String price_type, Integer voice_state, String currency_str, String symbol, String curr_prefix, String remarks, Integer is_pc, Integer is_app, Integer is_webhook, String webhook_url, String end_time, Integer isSelect, String preset_order_params, String orderAmount, String orderType, String orderUnit) {
        return new AlertLineItem(id2, db_key, show, db_key_cmp, show_cmp, style, mode, frequency, frequency_name, set_price, set_price_cmp, mode_info, mode_info_cmp, created_at, ews_time, expend, ews_price, ews_price_cmp, ews_type, price_type, voice_state, currency_str, symbol, curr_prefix, remarks, is_pc, is_app, is_webhook, webhook_url, end_time, isSelect, preset_order_params, orderAmount, orderType, orderUnit);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof AlertLineItem)) {
            return false;
        }
        AlertLineItem alertLineItem = (AlertLineItem) other;
        return AbstractC7609s.f(this.id, alertLineItem.id) && AbstractC7609s.f(this.db_key, alertLineItem.db_key) && AbstractC7609s.f(this.show, alertLineItem.show) && AbstractC7609s.f(this.db_key_cmp, alertLineItem.db_key_cmp) && AbstractC7609s.f(this.show_cmp, alertLineItem.show_cmp) && AbstractC7609s.f(this.style, alertLineItem.style) && AbstractC7609s.f(this.mode, alertLineItem.mode) && AbstractC7609s.f(this.frequency, alertLineItem.frequency) && AbstractC7609s.f(this.frequency_name, alertLineItem.frequency_name) && AbstractC7609s.f(this.set_price, alertLineItem.set_price) && AbstractC7609s.f(this.set_price_cmp, alertLineItem.set_price_cmp) && AbstractC7609s.f(this.mode_info, alertLineItem.mode_info) && AbstractC7609s.f(this.mode_info_cmp, alertLineItem.mode_info_cmp) && AbstractC7609s.f(this.created_at, alertLineItem.created_at) && AbstractC7609s.f(this.ews_time, alertLineItem.ews_time) && AbstractC7609s.f(this.expend, alertLineItem.expend) && AbstractC7609s.f(this.ews_price, alertLineItem.ews_price) && AbstractC7609s.f(this.ews_price_cmp, alertLineItem.ews_price_cmp) && AbstractC7609s.f(this.ews_type, alertLineItem.ews_type) && AbstractC7609s.f(this.price_type, alertLineItem.price_type) && AbstractC7609s.f(this.voice_state, alertLineItem.voice_state) && AbstractC7609s.f(this.currency_str, alertLineItem.currency_str) && AbstractC7609s.f(this.symbol, alertLineItem.symbol) && AbstractC7609s.f(this.curr_prefix, alertLineItem.curr_prefix) && AbstractC7609s.f(this.remarks, alertLineItem.remarks) && AbstractC7609s.f(this.is_pc, alertLineItem.is_pc) && AbstractC7609s.f(this.is_app, alertLineItem.is_app) && AbstractC7609s.f(this.is_webhook, alertLineItem.is_webhook) && AbstractC7609s.f(this.webhook_url, alertLineItem.webhook_url) && AbstractC7609s.f(this.end_time, alertLineItem.end_time) && AbstractC7609s.f(this.isSelect, alertLineItem.isSelect) && AbstractC7609s.f(this.preset_order_params, alertLineItem.preset_order_params) && AbstractC7609s.f(this.orderAmount, alertLineItem.orderAmount) && AbstractC7609s.f(this.orderType, alertLineItem.orderType) && AbstractC7609s.f(this.orderUnit, alertLineItem.orderUnit);
    }

    public final String getCreated_at() {
        return this.created_at;
    }

    public final String getCurr_prefix() {
        return this.curr_prefix;
    }

    public final String getCurrency_str() {
        return this.currency_str;
    }

    public final String getDb_key() {
        return this.db_key;
    }

    public final String getDb_key_cmp() {
        return this.db_key_cmp;
    }

    public final String getEnd_time() {
        return this.end_time;
    }

    public final String getEws_price() {
        return this.ews_price;
    }

    public final String getEws_price_cmp() {
        return this.ews_price_cmp;
    }

    public final String getEws_time() {
        return this.ews_time;
    }

    public final String getEws_type() {
        return this.ews_type;
    }

    public final String getExpend() {
        return this.expend;
    }

    public final String getFrequency() {
        return this.frequency;
    }

    public final String getFrequency_name() {
        return this.frequency_name;
    }

    public final String getId() {
        return this.id;
    }

    public final Integer getMode() {
        return this.mode;
    }

    public final String getMode_info() {
        return this.mode_info;
    }

    public final String getMode_info_cmp() {
        return this.mode_info_cmp;
    }

    public final String getOrderAmount() {
        return this.orderAmount;
    }

    public final String getOrderType() {
        return this.orderType;
    }

    public final String getOrderUnit() {
        return this.orderUnit;
    }

    public final String getPreset_order_params() {
        return this.preset_order_params;
    }

    public final String getPrice_type() {
        return this.price_type;
    }

    public final String getRemarks() {
        return this.remarks;
    }

    public final String getSet_price() {
        return this.set_price;
    }

    public final String getSet_price_cmp() {
        return this.set_price_cmp;
    }

    public final String getShow() {
        return this.show;
    }

    public final String getShow_cmp() {
        return this.show_cmp;
    }

    public final Integer getStyle() {
        return this.style;
    }

    public final String getSymbol() {
        return this.symbol;
    }

    public final Integer getVoice_state() {
        return this.voice_state;
    }

    public final String getWebhook_url() {
        return this.webhook_url;
    }

    public int hashCode() {
        String str = this.id;
        int iHashCode = (str == null ? 0 : str.hashCode()) * 31;
        String str2 = this.db_key;
        int iHashCode2 = (iHashCode + (str2 == null ? 0 : str2.hashCode())) * 31;
        String str3 = this.show;
        int iHashCode3 = (iHashCode2 + (str3 == null ? 0 : str3.hashCode())) * 31;
        String str4 = this.db_key_cmp;
        int iHashCode4 = (iHashCode3 + (str4 == null ? 0 : str4.hashCode())) * 31;
        String str5 = this.show_cmp;
        int iHashCode5 = (iHashCode4 + (str5 == null ? 0 : str5.hashCode())) * 31;
        Integer num = this.style;
        int iHashCode6 = (iHashCode5 + (num == null ? 0 : num.hashCode())) * 31;
        Integer num2 = this.mode;
        int iHashCode7 = (iHashCode6 + (num2 == null ? 0 : num2.hashCode())) * 31;
        String str6 = this.frequency;
        int iHashCode8 = (iHashCode7 + (str6 == null ? 0 : str6.hashCode())) * 31;
        String str7 = this.frequency_name;
        int iHashCode9 = (iHashCode8 + (str7 == null ? 0 : str7.hashCode())) * 31;
        String str8 = this.set_price;
        int iHashCode10 = (iHashCode9 + (str8 == null ? 0 : str8.hashCode())) * 31;
        String str9 = this.set_price_cmp;
        int iHashCode11 = (iHashCode10 + (str9 == null ? 0 : str9.hashCode())) * 31;
        String str10 = this.mode_info;
        int iHashCode12 = (iHashCode11 + (str10 == null ? 0 : str10.hashCode())) * 31;
        String str11 = this.mode_info_cmp;
        int iHashCode13 = (iHashCode12 + (str11 == null ? 0 : str11.hashCode())) * 31;
        String str12 = this.created_at;
        int iHashCode14 = (iHashCode13 + (str12 == null ? 0 : str12.hashCode())) * 31;
        String str13 = this.ews_time;
        int iHashCode15 = (iHashCode14 + (str13 == null ? 0 : str13.hashCode())) * 31;
        String str14 = this.expend;
        int iHashCode16 = (iHashCode15 + (str14 == null ? 0 : str14.hashCode())) * 31;
        String str15 = this.ews_price;
        int iHashCode17 = (iHashCode16 + (str15 == null ? 0 : str15.hashCode())) * 31;
        String str16 = this.ews_price_cmp;
        int iHashCode18 = (iHashCode17 + (str16 == null ? 0 : str16.hashCode())) * 31;
        String str17 = this.ews_type;
        int iHashCode19 = (iHashCode18 + (str17 == null ? 0 : str17.hashCode())) * 31;
        String str18 = this.price_type;
        int iHashCode20 = (iHashCode19 + (str18 == null ? 0 : str18.hashCode())) * 31;
        Integer num3 = this.voice_state;
        int iHashCode21 = (iHashCode20 + (num3 == null ? 0 : num3.hashCode())) * 31;
        String str19 = this.currency_str;
        int iHashCode22 = (iHashCode21 + (str19 == null ? 0 : str19.hashCode())) * 31;
        String str20 = this.symbol;
        int iHashCode23 = (iHashCode22 + (str20 == null ? 0 : str20.hashCode())) * 31;
        String str21 = this.curr_prefix;
        int iHashCode24 = (iHashCode23 + (str21 == null ? 0 : str21.hashCode())) * 31;
        String str22 = this.remarks;
        int iHashCode25 = (iHashCode24 + (str22 == null ? 0 : str22.hashCode())) * 31;
        Integer num4 = this.is_pc;
        int iHashCode26 = (iHashCode25 + (num4 == null ? 0 : num4.hashCode())) * 31;
        Integer num5 = this.is_app;
        int iHashCode27 = (iHashCode26 + (num5 == null ? 0 : num5.hashCode())) * 31;
        Integer num6 = this.is_webhook;
        int iHashCode28 = (iHashCode27 + (num6 == null ? 0 : num6.hashCode())) * 31;
        String str23 = this.webhook_url;
        int iHashCode29 = (iHashCode28 + (str23 == null ? 0 : str23.hashCode())) * 31;
        String str24 = this.end_time;
        int iHashCode30 = (iHashCode29 + (str24 == null ? 0 : str24.hashCode())) * 31;
        Integer num7 = this.isSelect;
        int iHashCode31 = (iHashCode30 + (num7 == null ? 0 : num7.hashCode())) * 31;
        String str25 = this.preset_order_params;
        int iHashCode32 = (iHashCode31 + (str25 == null ? 0 : str25.hashCode())) * 31;
        String str26 = this.orderAmount;
        int iHashCode33 = (iHashCode32 + (str26 == null ? 0 : str26.hashCode())) * 31;
        String str27 = this.orderType;
        int iHashCode34 = (iHashCode33 + (str27 == null ? 0 : str27.hashCode())) * 31;
        String str28 = this.orderUnit;
        return iHashCode34 + (str28 != null ? str28.hashCode() : 0);
    }

    public final Integer isSelect() {
        return this.isSelect;
    }

    public final Integer is_app() {
        return this.is_app;
    }

    public final Integer is_pc() {
        return this.is_pc;
    }

    public final Integer is_webhook() {
        return this.is_webhook;
    }

    public final void setOrderAmount(String str) {
        this.orderAmount = str;
    }

    public final void setOrderType(String str) {
        this.orderType = str;
    }

    public final void setOrderUnit(String str) {
        this.orderUnit = str;
    }

    public final void setPreset_order_params(String str) {
        this.preset_order_params = str;
    }

    public final void setSelect(Integer num) {
        this.isSelect = num;
    }

    public String toString() {
        return "AlertLineItem(id=" + this.id + ", db_key=" + this.db_key + ", show=" + this.show + ", db_key_cmp=" + this.db_key_cmp + ", show_cmp=" + this.show_cmp + ", style=" + this.style + ", mode=" + this.mode + ", frequency=" + this.frequency + ", frequency_name=" + this.frequency_name + ", set_price=" + this.set_price + ", set_price_cmp=" + this.set_price_cmp + ", mode_info=" + this.mode_info + ", mode_info_cmp=" + this.mode_info_cmp + ", created_at=" + this.created_at + ", ews_time=" + this.ews_time + ", expend=" + this.expend + ", ews_price=" + this.ews_price + ", ews_price_cmp=" + this.ews_price_cmp + ", ews_type=" + this.ews_type + ", price_type=" + this.price_type + ", voice_state=" + this.voice_state + ", currency_str=" + this.currency_str + ", symbol=" + this.symbol + ", curr_prefix=" + this.curr_prefix + ", remarks=" + this.remarks + ", is_pc=" + this.is_pc + ", is_app=" + this.is_app + ", is_webhook=" + this.is_webhook + ", webhook_url=" + this.webhook_url + ", end_time=" + this.end_time + ", isSelect=" + this.isSelect + ", preset_order_params=" + this.preset_order_params + ", orderAmount=" + this.orderAmount + ", orderType=" + this.orderType + ", orderUnit=" + this.orderUnit + ')';
    }
}
