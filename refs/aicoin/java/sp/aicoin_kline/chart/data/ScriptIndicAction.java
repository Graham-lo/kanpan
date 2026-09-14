package sp.aicoin_kline.chart.data;

import androidx.annotation.Keep;
import com.tencent.wcdb.database.SQLiteGlobal;
import kk.d;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import okhttp3.dnsoverhttps.DnsOverHttps;
import okhttp3.internal.http2.Http2;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000(\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u000b\n\u0002\b\b\n\u0002\u0010\b\n\u0002\bF\b\u0087\b\u0018\u00002\u00020\u0001B÷\u0001\u0012\b\b\u0002\u0010\u0002\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0004\u001a\u00020\u0003\u0012\u0006\u0010\u0005\u001a\u00020\u0006\u0012\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\b\u0012\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u000e\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u000f\u001a\u0004\u0018\u00010\u0003\u0012\b\b\u0002\u0010\u0010\u001a\u00020\u0011\u0012\n\b\u0002\u0010\u0012\u001a\u0004\u0018\u00010\u0003\u0012\b\b\u0002\u0010\u0013\u001a\u00020\u0011\u0012\n\b\u0002\u0010\u0014\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0015\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0016\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0017\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0018\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0019\u001a\u0004\u0018\u00010\b\u0012\n\b\u0002\u0010\u001a\u001a\u0004\u0018\u00010\b¢\u0006\u0004\b\u001b\u0010\u001cJ\t\u0010<\u001a\u00020\u0003HÆ\u0003J\t\u0010=\u001a\u00020\u0003HÆ\u0003J\t\u0010>\u001a\u00020\u0006HÆ\u0003J\u0010\u0010?\u001a\u0004\u0018\u00010\bHÆ\u0003¢\u0006\u0002\u0010#J\u000b\u0010@\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010A\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010B\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010C\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010D\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010E\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010F\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\t\u0010G\u001a\u00020\u0011HÆ\u0003J\u000b\u0010H\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\t\u0010I\u001a\u00020\u0011HÆ\u0003J\u000b\u0010J\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010K\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010L\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010M\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010N\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0010\u0010O\u001a\u0004\u0018\u00010\bHÆ\u0003¢\u0006\u0002\u0010#J\u0010\u0010P\u001a\u0004\u0018\u00010\bHÆ\u0003¢\u0006\u0002\u0010#J\u0080\u0002\u0010Q\u001a\u00020\u00002\b\b\u0002\u0010\u0002\u001a\u00020\u00032\b\b\u0002\u0010\u0004\u001a\u00020\u00032\b\b\u0002\u0010\u0005\u001a\u00020\u00062\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\b2\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u000e\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u000f\u001a\u0004\u0018\u00010\u00032\b\b\u0002\u0010\u0010\u001a\u00020\u00112\n\b\u0002\u0010\u0012\u001a\u0004\u0018\u00010\u00032\b\b\u0002\u0010\u0013\u001a\u00020\u00112\n\b\u0002\u0010\u0014\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0015\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0016\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0017\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0018\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0019\u001a\u0004\u0018\u00010\b2\n\b\u0002\u0010\u001a\u001a\u0004\u0018\u00010\bHÆ\u0001¢\u0006\u0002\u0010RJ\u0013\u0010S\u001a\u00020\b2\b\u0010T\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010U\u001a\u00020\u0011HÖ\u0001J\t\u0010V\u001a\u00020\u0003HÖ\u0001R\u0011\u0010\u0002\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u001d\u0010\u001eR\u0011\u0010\u0004\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u001f\u0010\u001eR\u0011\u0010\u0005\u001a\u00020\u0006¢\u0006\b\n\u0000\u001a\u0004\b \u0010!R\u001e\u0010\u0007\u001a\u0004\u0018\u00010\bX\u0086\u000e¢\u0006\u0010\n\u0002\u0010&\u001a\u0004\b\"\u0010#\"\u0004\b$\u0010%R\u0013\u0010\t\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b'\u0010\u001eR\u0013\u0010\n\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b(\u0010\u001eR\u0013\u0010\u000b\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b)\u0010\u001eR\u0013\u0010\f\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b*\u0010\u001eR\u0013\u0010\r\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b+\u0010\u001eR\u0013\u0010\u000e\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b,\u0010\u001eR\u0013\u0010\u000f\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b-\u0010\u001eR\u001a\u0010\u0010\u001a\u00020\u0011X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b.\u0010/\"\u0004\b0\u00101R\u0013\u0010\u0012\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b2\u0010\u001eR\u001a\u0010\u0013\u001a\u00020\u0011X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b3\u0010/\"\u0004\b4\u00101R\u0013\u0010\u0014\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b5\u0010\u001eR\u0013\u0010\u0015\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b6\u0010\u001eR\u0013\u0010\u0016\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b7\u0010\u001eR\u0013\u0010\u0017\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b8\u0010\u001eR\u0013\u0010\u0018\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b9\u0010\u001eR\u0015\u0010\u0019\u001a\u0004\u0018\u00010\b¢\u0006\n\n\u0002\u0010&\u001a\u0004\b:\u0010#R\u0015\u0010\u001a\u001a\u0004\u0018\u00010\b¢\u0006\n\n\u0002\u0010&\u001a\u0004\b;\u0010#¨\u0006W"}, d2 = {"Lsp/aicoin_kline/chart/data/ScriptIndicAction;", "", "action", "", "id", "output", "Lsp/aicoin_kline/chart/data/ActionOutput;", "display", "", "refSeries", "retVal", "series", "title", "series1", "series2", "offset", "intOffset", "", "showLast", "intShowLast", "histBase", "high", "open", "low", "close", "excludeRange", "trackPrice", "<init>", "(Ljava/lang/String;Ljava/lang/String;Lsp/aicoin_kline/chart/data/ActionOutput;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;ILjava/lang/String;ILjava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/Boolean;)V", "getAction", "()Ljava/lang/String;", "getId", "getOutput", "()Lsp/aicoin_kline/chart/data/ActionOutput;", "getDisplay", "()Ljava/lang/Boolean;", "setDisplay", "(Ljava/lang/Boolean;)V", "Ljava/lang/Boolean;", "getRefSeries", "getRetVal", "getSeries", "getTitle", "getSeries1", "getSeries2", "getOffset", "getIntOffset", "()I", "setIntOffset", "(I)V", "getShowLast", "getIntShowLast", "setIntShowLast", "getHistBase", "getHigh", "getOpen", "getLow", "getClose", "getExcludeRange", "getTrackPrice", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "component9", "component10", "component11", "component12", "component13", "component14", "component15", "component16", "component17", "component18", "component19", "component20", "component21", "copy", "(Ljava/lang/String;Ljava/lang/String;Lsp/aicoin_kline/chart/data/ActionOutput;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;ILjava/lang/String;ILjava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/Boolean;)Lsp/aicoin_kline/chart/data/ScriptIndicAction;", "equals", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class ScriptIndicAction {
    private final String action;
    private final String close;
    private Boolean display;
    private final Boolean excludeRange;
    private final String high;
    private final String histBase;
    private final String id;
    private int intOffset;
    private int intShowLast;
    private final String low;
    private final String offset;
    private final String open;
    private final ActionOutput output;
    private final String refSeries;
    private final String retVal;
    private final String series;
    private final String series1;
    private final String series2;
    private final String showLast;
    private final String title;
    private final Boolean trackPrice;

    public ScriptIndicAction(String str, String str2, ActionOutput actionOutput, Boolean bool, String str3, String str4, String str5, String str6, String str7, String str8, String str9, int i10, String str10, int i11, String str11, String str12, String str13, String str14, String str15, Boolean bool2, Boolean bool3) {
        this.action = str;
        this.id = str2;
        this.output = actionOutput;
        this.display = bool;
        this.refSeries = str3;
        this.retVal = str4;
        this.series = str5;
        this.title = str6;
        this.series1 = str7;
        this.series2 = str8;
        this.offset = str9;
        this.intOffset = i10;
        this.showLast = str10;
        this.intShowLast = i11;
        this.histBase = str11;
        this.high = str12;
        this.open = str13;
        this.low = str14;
        this.close = str15;
        this.excludeRange = bool2;
        this.trackPrice = bool3;
    }

    public /* synthetic */ ScriptIndicAction(String str, String str2, ActionOutput actionOutput, Boolean bool, String str3, String str4, String str5, String str6, String str7, String str8, String str9, int i10, String str10, int i11, String str11, String str12, String str13, String str14, String str15, Boolean bool2, Boolean bool3, int i12, DefaultConstructorMarker defaultConstructorMarker) {
        this((i12 & 1) != 0 ? "" : str, (i12 & 2) != 0 ? "" : str2, actionOutput, (i12 & 8) != 0 ? Boolean.TRUE : bool, (i12 & 16) != 0 ? "" : str3, (i12 & 32) != 0 ? "" : str4, (i12 & 64) != 0 ? "" : str5, (i12 & 128) != 0 ? "" : str6, (i12 & 256) != 0 ? "" : str7, (i12 & 512) != 0 ? "" : str8, (i12 & 1024) != 0 ? "0" : str9, (i12 & 2048) != 0 ? 0 : i10, (i12 & 4096) != 0 ? "-1" : str10, (i12 & 8192) != 0 ? -1 : i11, (i12 & Http2.INITIAL_MAX_FRAME_SIZE) != 0 ? "0" : str11, (32768 & i12) != 0 ? "0" : str12, (65536 & i12) != 0 ? "0" : str13, (131072 & i12) != 0 ? "0" : str14, (262144 & i12) != 0 ? "0" : str15, (524288 & i12) != 0 ? Boolean.FALSE : bool2, (i12 & 1048576) != 0 ? Boolean.FALSE : bool3);
    }

    public static /* synthetic */ ScriptIndicAction copy$default(ScriptIndicAction scriptIndicAction, String str, String str2, ActionOutput actionOutput, Boolean bool, String str3, String str4, String str5, String str6, String str7, String str8, String str9, int i10, String str10, int i11, String str11, String str12, String str13, String str14, String str15, Boolean bool2, Boolean bool3, int i12, Object obj) {
        Boolean bool4;
        Boolean bool5;
        String str16 = (i12 & 1) != 0 ? scriptIndicAction.action : str;
        String str17 = (i12 & 2) != 0 ? scriptIndicAction.id : str2;
        ActionOutput actionOutput2 = (i12 & 4) != 0 ? scriptIndicAction.output : actionOutput;
        Boolean bool6 = (i12 & 8) != 0 ? scriptIndicAction.display : bool;
        String str18 = (i12 & 16) != 0 ? scriptIndicAction.refSeries : str3;
        String str19 = (i12 & 32) != 0 ? scriptIndicAction.retVal : str4;
        String str20 = (i12 & 64) != 0 ? scriptIndicAction.series : str5;
        String str21 = (i12 & 128) != 0 ? scriptIndicAction.title : str6;
        String str22 = (i12 & 256) != 0 ? scriptIndicAction.series1 : str7;
        String str23 = (i12 & 512) != 0 ? scriptIndicAction.series2 : str8;
        String str24 = (i12 & 1024) != 0 ? scriptIndicAction.offset : str9;
        int i13 = (i12 & 2048) != 0 ? scriptIndicAction.intOffset : i10;
        String str25 = (i12 & 4096) != 0 ? scriptIndicAction.showLast : str10;
        int i14 = (i12 & 8192) != 0 ? scriptIndicAction.intShowLast : i11;
        String str26 = str16;
        String str27 = (i12 & Http2.INITIAL_MAX_FRAME_SIZE) != 0 ? scriptIndicAction.histBase : str11;
        String str28 = (i12 & 32768) != 0 ? scriptIndicAction.high : str12;
        String str29 = (i12 & DnsOverHttps.MAX_RESPONSE_SIZE) != 0 ? scriptIndicAction.open : str13;
        String str30 = (i12 & 131072) != 0 ? scriptIndicAction.low : str14;
        String str31 = (i12 & 262144) != 0 ? scriptIndicAction.close : str15;
        Boolean bool7 = (i12 & SQLiteGlobal.journalSizeLimit) != 0 ? scriptIndicAction.excludeRange : bool2;
        if ((i12 & 1048576) != 0) {
            bool5 = bool7;
            bool4 = scriptIndicAction.trackPrice;
        } else {
            bool4 = bool3;
            bool5 = bool7;
        }
        return scriptIndicAction.copy(str26, str17, actionOutput2, bool6, str18, str19, str20, str21, str22, str23, str24, i13, str25, i14, str27, str28, str29, str30, str31, bool5, bool4);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final String getAction() {
        return this.action;
    }

    /* JADX INFO: renamed from: component10, reason: from getter */
    public final String getSeries2() {
        return this.series2;
    }

    /* JADX INFO: renamed from: component11, reason: from getter */
    public final String getOffset() {
        return this.offset;
    }

    /* JADX INFO: renamed from: component12, reason: from getter */
    public final int getIntOffset() {
        return this.intOffset;
    }

    /* JADX INFO: renamed from: component13, reason: from getter */
    public final String getShowLast() {
        return this.showLast;
    }

    /* JADX INFO: renamed from: component14, reason: from getter */
    public final int getIntShowLast() {
        return this.intShowLast;
    }

    /* JADX INFO: renamed from: component15, reason: from getter */
    public final String getHistBase() {
        return this.histBase;
    }

    /* JADX INFO: renamed from: component16, reason: from getter */
    public final String getHigh() {
        return this.high;
    }

    /* JADX INFO: renamed from: component17, reason: from getter */
    public final String getOpen() {
        return this.open;
    }

    /* JADX INFO: renamed from: component18, reason: from getter */
    public final String getLow() {
        return this.low;
    }

    /* JADX INFO: renamed from: component19, reason: from getter */
    public final String getClose() {
        return this.close;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final String getId() {
        return this.id;
    }

    /* JADX INFO: renamed from: component20, reason: from getter */
    public final Boolean getExcludeRange() {
        return this.excludeRange;
    }

    /* JADX INFO: renamed from: component21, reason: from getter */
    public final Boolean getTrackPrice() {
        return this.trackPrice;
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    public final ActionOutput getOutput() {
        return this.output;
    }

    /* JADX INFO: renamed from: component4, reason: from getter */
    public final Boolean getDisplay() {
        return this.display;
    }

    /* JADX INFO: renamed from: component5, reason: from getter */
    public final String getRefSeries() {
        return this.refSeries;
    }

    /* JADX INFO: renamed from: component6, reason: from getter */
    public final String getRetVal() {
        return this.retVal;
    }

    /* JADX INFO: renamed from: component7, reason: from getter */
    public final String getSeries() {
        return this.series;
    }

    /* JADX INFO: renamed from: component8, reason: from getter */
    public final String getTitle() {
        return this.title;
    }

    /* JADX INFO: renamed from: component9, reason: from getter */
    public final String getSeries1() {
        return this.series1;
    }

    public final ScriptIndicAction copy(String action, String id2, ActionOutput output, Boolean display, String refSeries, String retVal, String series, String title, String series1, String series2, String offset, int intOffset, String showLast, int intShowLast, String histBase, String high, String open, String low, String close, Boolean excludeRange, Boolean trackPrice) {
        return new ScriptIndicAction(action, id2, output, display, refSeries, retVal, series, title, series1, series2, offset, intOffset, showLast, intShowLast, histBase, high, open, low, close, excludeRange, trackPrice);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof ScriptIndicAction)) {
            return false;
        }
        ScriptIndicAction scriptIndicAction = (ScriptIndicAction) other;
        return AbstractC7609s.f(this.action, scriptIndicAction.action) && AbstractC7609s.f(this.id, scriptIndicAction.id) && AbstractC7609s.f(this.output, scriptIndicAction.output) && AbstractC7609s.f(this.display, scriptIndicAction.display) && AbstractC7609s.f(this.refSeries, scriptIndicAction.refSeries) && AbstractC7609s.f(this.retVal, scriptIndicAction.retVal) && AbstractC7609s.f(this.series, scriptIndicAction.series) && AbstractC7609s.f(this.title, scriptIndicAction.title) && AbstractC7609s.f(this.series1, scriptIndicAction.series1) && AbstractC7609s.f(this.series2, scriptIndicAction.series2) && AbstractC7609s.f(this.offset, scriptIndicAction.offset) && this.intOffset == scriptIndicAction.intOffset && AbstractC7609s.f(this.showLast, scriptIndicAction.showLast) && this.intShowLast == scriptIndicAction.intShowLast && AbstractC7609s.f(this.histBase, scriptIndicAction.histBase) && AbstractC7609s.f(this.high, scriptIndicAction.high) && AbstractC7609s.f(this.open, scriptIndicAction.open) && AbstractC7609s.f(this.low, scriptIndicAction.low) && AbstractC7609s.f(this.close, scriptIndicAction.close) && AbstractC7609s.f(this.excludeRange, scriptIndicAction.excludeRange) && AbstractC7609s.f(this.trackPrice, scriptIndicAction.trackPrice);
    }

    public final String getAction() {
        return this.action;
    }

    public final String getClose() {
        return this.close;
    }

    public final Boolean getDisplay() {
        return this.display;
    }

    public final Boolean getExcludeRange() {
        return this.excludeRange;
    }

    public final String getHigh() {
        return this.high;
    }

    public final String getHistBase() {
        return this.histBase;
    }

    public final String getId() {
        return this.id;
    }

    public final int getIntOffset() {
        return this.intOffset;
    }

    public final int getIntShowLast() {
        return this.intShowLast;
    }

    public final String getLow() {
        return this.low;
    }

    public final String getOffset() {
        return this.offset;
    }

    public final String getOpen() {
        return this.open;
    }

    public final ActionOutput getOutput() {
        return this.output;
    }

    public final String getRefSeries() {
        return this.refSeries;
    }

    public final String getRetVal() {
        return this.retVal;
    }

    public final String getSeries() {
        return this.series;
    }

    public final String getSeries1() {
        return this.series1;
    }

    public final String getSeries2() {
        return this.series2;
    }

    public final String getShowLast() {
        return this.showLast;
    }

    public final String getTitle() {
        return this.title;
    }

    public final Boolean getTrackPrice() {
        return this.trackPrice;
    }

    public int hashCode() {
        int iHashCode = (this.output.hashCode() + d.a(this.id, this.action.hashCode() * 31, 31)) * 31;
        Boolean bool = this.display;
        int iHashCode2 = (iHashCode + (bool == null ? 0 : bool.hashCode())) * 31;
        String str = this.refSeries;
        int iHashCode3 = (iHashCode2 + (str == null ? 0 : str.hashCode())) * 31;
        String str2 = this.retVal;
        int iHashCode4 = (iHashCode3 + (str2 == null ? 0 : str2.hashCode())) * 31;
        String str3 = this.series;
        int iHashCode5 = (iHashCode4 + (str3 == null ? 0 : str3.hashCode())) * 31;
        String str4 = this.title;
        int iHashCode6 = (iHashCode5 + (str4 == null ? 0 : str4.hashCode())) * 31;
        String str5 = this.series1;
        int iHashCode7 = (iHashCode6 + (str5 == null ? 0 : str5.hashCode())) * 31;
        String str6 = this.series2;
        int iHashCode8 = (iHashCode7 + (str6 == null ? 0 : str6.hashCode())) * 31;
        String str7 = this.offset;
        int iHashCode9 = (Integer.hashCode(this.intOffset) + ((iHashCode8 + (str7 == null ? 0 : str7.hashCode())) * 31)) * 31;
        String str8 = this.showLast;
        int iHashCode10 = (Integer.hashCode(this.intShowLast) + ((iHashCode9 + (str8 == null ? 0 : str8.hashCode())) * 31)) * 31;
        String str9 = this.histBase;
        int iHashCode11 = (iHashCode10 + (str9 == null ? 0 : str9.hashCode())) * 31;
        String str10 = this.high;
        int iHashCode12 = (iHashCode11 + (str10 == null ? 0 : str10.hashCode())) * 31;
        String str11 = this.open;
        int iHashCode13 = (iHashCode12 + (str11 == null ? 0 : str11.hashCode())) * 31;
        String str12 = this.low;
        int iHashCode14 = (iHashCode13 + (str12 == null ? 0 : str12.hashCode())) * 31;
        String str13 = this.close;
        int iHashCode15 = (iHashCode14 + (str13 == null ? 0 : str13.hashCode())) * 31;
        Boolean bool2 = this.excludeRange;
        int iHashCode16 = (iHashCode15 + (bool2 == null ? 0 : bool2.hashCode())) * 31;
        Boolean bool3 = this.trackPrice;
        return iHashCode16 + (bool3 != null ? bool3.hashCode() : 0);
    }

    public final void setDisplay(Boolean bool) {
        this.display = bool;
    }

    public final void setIntOffset(int i10) {
        this.intOffset = i10;
    }

    public final void setIntShowLast(int i10) {
        this.intShowLast = i10;
    }

    public String toString() {
        return "ScriptIndicAction(action=" + this.action + ", id=" + this.id + ", output=" + this.output + ", display=" + this.display + ", refSeries=" + this.refSeries + ", retVal=" + this.retVal + ", series=" + this.series + ", title=" + this.title + ", series1=" + this.series1 + ", series2=" + this.series2 + ", offset=" + this.offset + ", intOffset=" + this.intOffset + ", showLast=" + this.showLast + ", intShowLast=" + this.intShowLast + ", histBase=" + this.histBase + ", high=" + this.high + ", open=" + this.open + ", low=" + this.low + ", close=" + this.close + ", excludeRange=" + this.excludeRange + ", trackPrice=" + this.trackPrice + ')';
    }
}
