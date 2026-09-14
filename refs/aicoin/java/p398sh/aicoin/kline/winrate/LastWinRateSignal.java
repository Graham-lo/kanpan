package p398sh.aicoin.kline.winrate;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import com.tencent.android.tpush.common.MessageKey;
import kotlin.Metadata;
import p167hg.AbstractC7609s;
import p254m.aicoin.alert.record.T;
import p398sh.aicoin.search.data.remote.SearchRemoteDataSource;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000\"\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000e\n\u0002\b\t\n\u0002\u0010\u000b\n\u0002\b'\n\u0002\u0010\b\n\u0002\b\u0002\b\u0087\b\u0018\u00002\u00020\u0001Bw\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\u0006\u0010\u0004\u001a\u00020\u0003\u0012\u0006\u0010\u0005\u001a\u00020\u0003\u0012\u0006\u0010\u0006\u001a\u00020\u0003\u0012\u0006\u0010\u0007\u001a\u00020\u0003\u0012\u0006\u0010\b\u001a\u00020\u0003\u0012\u0006\u0010\t\u001a\u00020\u0003\u0012\u0006\u0010\n\u001a\u00020\u0003\u0012\u0006\u0010\u000b\u001a\u00020\u0003\u0012\u0006\u0010\f\u001a\u00020\r\u0012\u0006\u0010\u000e\u001a\u00020\u0003\u0012\u0006\u0010\u000f\u001a\u00020\r\u0012\u0006\u0010\u0010\u001a\u00020\u0003\u0012\u0006\u0010\u0011\u001a\u00020\r¢\u0006\u0004\b\u0012\u0010\u0013J\t\u0010#\u001a\u00020\u0003HÆ\u0003J\t\u0010$\u001a\u00020\u0003HÆ\u0003J\t\u0010%\u001a\u00020\u0003HÆ\u0003J\t\u0010&\u001a\u00020\u0003HÆ\u0003J\t\u0010'\u001a\u00020\u0003HÆ\u0003J\t\u0010(\u001a\u00020\u0003HÆ\u0003J\t\u0010)\u001a\u00020\u0003HÆ\u0003J\t\u0010*\u001a\u00020\u0003HÆ\u0003J\t\u0010+\u001a\u00020\u0003HÆ\u0003J\t\u0010,\u001a\u00020\rHÆ\u0003J\t\u0010-\u001a\u00020\u0003HÆ\u0003J\t\u0010.\u001a\u00020\rHÆ\u0003J\t\u0010/\u001a\u00020\u0003HÆ\u0003J\t\u00100\u001a\u00020\rHÆ\u0003J\u0095\u0001\u00101\u001a\u00020\u00002\b\b\u0002\u0010\u0002\u001a\u00020\u00032\b\b\u0002\u0010\u0004\u001a\u00020\u00032\b\b\u0002\u0010\u0005\u001a\u00020\u00032\b\b\u0002\u0010\u0006\u001a\u00020\u00032\b\b\u0002\u0010\u0007\u001a\u00020\u00032\b\b\u0002\u0010\b\u001a\u00020\u00032\b\b\u0002\u0010\t\u001a\u00020\u00032\b\b\u0002\u0010\n\u001a\u00020\u00032\b\b\u0002\u0010\u000b\u001a\u00020\u00032\b\b\u0002\u0010\f\u001a\u00020\r2\b\b\u0002\u0010\u000e\u001a\u00020\u00032\b\b\u0002\u0010\u000f\u001a\u00020\r2\b\b\u0002\u0010\u0010\u001a\u00020\u00032\b\b\u0002\u0010\u0011\u001a\u00020\rHÆ\u0001J\u0013\u00102\u001a\u00020\r2\b\u00103\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u00104\u001a\u000205HÖ\u0001J\t\u00106\u001a\u00020\u0003HÖ\u0001R\u0011\u0010\u0002\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0014\u0010\u0015R\u0016\u0010\u0004\u001a\u00020\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0016\u0010\u0015R\u0011\u0010\u0005\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0017\u0010\u0015R\u0011\u0010\u0006\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0018\u0010\u0015R\u0011\u0010\u0007\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0019\u0010\u0015R\u0011\u0010\b\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u001a\u0010\u0015R\u0011\u0010\t\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u001b\u0010\u0015R\u0011\u0010\n\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u001c\u0010\u0015R\u0016\u0010\u000b\u001a\u00020\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u001d\u0010\u0015R\u0016\u0010\f\u001a\u00020\r8\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u001e\u0010\u001fR\u0016\u0010\u000e\u001a\u00020\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b \u0010\u0015R\u0016\u0010\u000f\u001a\u00020\r8\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b!\u0010\u001fR\u0011\u0010\u0010\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\"\u0010\u0015R\u0016\u0010\u0011\u001a\u00020\r8\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0011\u0010\u001f¨\u00067"}, d2 = {"Lsh/aicoin/kline/winrate/LastWinRateSignal;", "", "id", "", "signalType", "side", "state", SearchRemoteDataSource.HTTP_PARSE_KEY_ITEM_COIN_NAME, "currency", T.MARKET, "key", "winRate", "winRateShow", "", "capitalRate", "capitalRateShow", MessageKey.MSG_DATE, "isVip", "<init>", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;ZLjava/lang/String;ZLjava/lang/String;Z)V", "getId", "()Ljava/lang/String;", "getSignalType", "getSide", "getState", "getShow", "getCurrency", "getMarket", "getKey", "getWinRate", "getWinRateShow", "()Z", "getCapitalRate", "getCapitalRateShow", "getDate", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "component9", "component10", "component11", "component12", "component13", "component14", "copy", "equals", "other", "hashCode", "", "toString", "sh-kline_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class LastWinRateSignal {

    @SerializedName("capital_rate")
    private final String capitalRate;

    @SerializedName("capital_rate_show")
    private final boolean capitalRateShow;
    private final String currency;
    private final String date;
    private final String id;

    @SerializedName("is_vip")
    private final boolean isVip;
    private final String key;
    private final String market;
    private final String show;
    private final String side;

    @SerializedName("signal_type")
    private final String signalType;
    private final String state;

    @SerializedName("win_rate")
    private final String winRate;

    @SerializedName("win_rate_show")
    private final boolean winRateShow;

    public LastWinRateSignal(String str, String str2, String str3, String str4, String str5, String str6, String str7, String str8, String str9, boolean z10, String str10, boolean z11, String str11, boolean z12) {
        this.id = str;
        this.signalType = str2;
        this.side = str3;
        this.state = str4;
        this.show = str5;
        this.currency = str6;
        this.market = str7;
        this.key = str8;
        this.winRate = str9;
        this.winRateShow = z10;
        this.capitalRate = str10;
        this.capitalRateShow = z11;
        this.date = str11;
        this.isVip = z12;
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final String getId() {
        return this.id;
    }

    /* JADX INFO: renamed from: component10, reason: from getter */
    public final boolean getWinRateShow() {
        return this.winRateShow;
    }

    /* JADX INFO: renamed from: component11, reason: from getter */
    public final String getCapitalRate() {
        return this.capitalRate;
    }

    /* JADX INFO: renamed from: component12, reason: from getter */
    public final boolean getCapitalRateShow() {
        return this.capitalRateShow;
    }

    /* JADX INFO: renamed from: component13, reason: from getter */
    public final String getDate() {
        return this.date;
    }

    /* JADX INFO: renamed from: component14, reason: from getter */
    public final boolean getIsVip() {
        return this.isVip;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final String getSignalType() {
        return this.signalType;
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    public final String getSide() {
        return this.side;
    }

    /* JADX INFO: renamed from: component4, reason: from getter */
    public final String getState() {
        return this.state;
    }

    /* JADX INFO: renamed from: component5, reason: from getter */
    public final String getShow() {
        return this.show;
    }

    /* JADX INFO: renamed from: component6, reason: from getter */
    public final String getCurrency() {
        return this.currency;
    }

    /* JADX INFO: renamed from: component7, reason: from getter */
    public final String getMarket() {
        return this.market;
    }

    /* JADX INFO: renamed from: component8, reason: from getter */
    public final String getKey() {
        return this.key;
    }

    /* JADX INFO: renamed from: component9, reason: from getter */
    public final String getWinRate() {
        return this.winRate;
    }

    public final LastWinRateSignal copy(String id2, String signalType, String side, String state, String show, String currency, String market, String key, String winRate, boolean winRateShow, String capitalRate, boolean capitalRateShow, String date, boolean isVip) {
        return new LastWinRateSignal(id2, signalType, side, state, show, currency, market, key, winRate, winRateShow, capitalRate, capitalRateShow, date, isVip);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof LastWinRateSignal)) {
            return false;
        }
        LastWinRateSignal lastWinRateSignal = (LastWinRateSignal) other;
        return AbstractC7609s.f(this.id, lastWinRateSignal.id) && AbstractC7609s.f(this.signalType, lastWinRateSignal.signalType) && AbstractC7609s.f(this.side, lastWinRateSignal.side) && AbstractC7609s.f(this.state, lastWinRateSignal.state) && AbstractC7609s.f(this.show, lastWinRateSignal.show) && AbstractC7609s.f(this.currency, lastWinRateSignal.currency) && AbstractC7609s.f(this.market, lastWinRateSignal.market) && AbstractC7609s.f(this.key, lastWinRateSignal.key) && AbstractC7609s.f(this.winRate, lastWinRateSignal.winRate) && this.winRateShow == lastWinRateSignal.winRateShow && AbstractC7609s.f(this.capitalRate, lastWinRateSignal.capitalRate) && this.capitalRateShow == lastWinRateSignal.capitalRateShow && AbstractC7609s.f(this.date, lastWinRateSignal.date) && this.isVip == lastWinRateSignal.isVip;
    }

    public final String getCapitalRate() {
        return this.capitalRate;
    }

    public final boolean getCapitalRateShow() {
        return this.capitalRateShow;
    }

    public final String getCurrency() {
        return this.currency;
    }

    public final String getDate() {
        return this.date;
    }

    public final String getId() {
        return this.id;
    }

    public final String getKey() {
        return this.key;
    }

    public final String getMarket() {
        return this.market;
    }

    public final String getShow() {
        return this.show;
    }

    public final String getSide() {
        return this.side;
    }

    public final String getSignalType() {
        return this.signalType;
    }

    public final String getState() {
        return this.state;
    }

    public final String getWinRate() {
        return this.winRate;
    }

    public final boolean getWinRateShow() {
        return this.winRateShow;
    }

    public int hashCode() {
        return (((((((((((((((((((((((((this.id.hashCode() * 31) + this.signalType.hashCode()) * 31) + this.side.hashCode()) * 31) + this.state.hashCode()) * 31) + this.show.hashCode()) * 31) + this.currency.hashCode()) * 31) + this.market.hashCode()) * 31) + this.key.hashCode()) * 31) + this.winRate.hashCode()) * 31) + Boolean.hashCode(this.winRateShow)) * 31) + this.capitalRate.hashCode()) * 31) + Boolean.hashCode(this.capitalRateShow)) * 31) + this.date.hashCode()) * 31) + Boolean.hashCode(this.isVip);
    }

    public final boolean isVip() {
        return this.isVip;
    }

    public String toString() {
        return "LastWinRateSignal(id=" + this.id + ", signalType=" + this.signalType + ", side=" + this.side + ", state=" + this.state + ", show=" + this.show + ", currency=" + this.currency + ", market=" + this.market + ", key=" + this.key + ", winRate=" + this.winRate + ", winRateShow=" + this.winRateShow + ", capitalRate=" + this.capitalRate + ", capitalRateShow=" + this.capitalRateShow + ", date=" + this.date + ", isVip=" + this.isVip + ")";
    }
}
