package sp.aicoin_kline.chart.data;

import android.os.Parcel;
import android.os.Parcelable;
import androidx.annotation.Keep;
import com.umeng.analytics.pro.am;
import kk.d;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000F\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\t\n\u0002\b\u0005\n\u0002\u0010\u0006\n\u0002\b\u0004\n\u0002\u0010\b\n\u0002\b\u0002\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0002\b\u0019\n\u0002\u0010\u0000\n\u0002\b)\b\u0087\b\u0018\u0000 [2\u00020\u0001:\u0001\\B\u0089\u0001\u0012\b\b\u0002\u0010\u0003\u001a\u00020\u0002\u0012\b\b\u0002\u0010\u0005\u001a\u00020\u0004\u0012\b\b\u0002\u0010\u0006\u001a\u00020\u0004\u0012\b\b\u0002\u0010\u0007\u001a\u00020\u0002\u0012\b\b\u0002\u0010\b\u001a\u00020\u0002\u0012\b\b\u0002\u0010\t\u001a\u00020\u0002\u0012\b\b\u0002\u0010\u000b\u001a\u00020\n\u0012\b\b\u0002\u0010\f\u001a\u00020\n\u0012\b\b\u0002\u0010\r\u001a\u00020\n\u0012\b\b\u0002\u0010\u000e\u001a\u00020\n\u0012\b\b\u0002\u0010\u0010\u001a\u00020\u000f\u0012\b\b\u0002\u0010\u0011\u001a\u00020\u0002\u0012\b\b\u0002\u0010\u0013\u001a\u00020\u0012¢\u0006\u0004\b\u0014\u0010\u0015B\u0011\b\u0016\u0012\u0006\u0010\u0017\u001a\u00020\u0016¢\u0006\u0004\b\u0014\u0010\u0018J\u001f\u0010\u001b\u001a\u00020\u001a2\u0006\u0010\u0017\u001a\u00020\u00162\u0006\u0010\u0019\u001a\u00020\u000fH\u0016¢\u0006\u0004\b\u001b\u0010\u001cJ\u000f\u0010\u001d\u001a\u00020\u000fH\u0016¢\u0006\u0004\b\u001d\u0010\u001eJ\u0010\u0010\u001f\u001a\u00020\u0002HÆ\u0003¢\u0006\u0004\b\u001f\u0010 J\u0010\u0010!\u001a\u00020\u0004HÆ\u0003¢\u0006\u0004\b!\u0010\"J\u0010\u0010#\u001a\u00020\u0004HÆ\u0003¢\u0006\u0004\b#\u0010\"J\u0010\u0010$\u001a\u00020\u0002HÆ\u0003¢\u0006\u0004\b$\u0010 J\u0010\u0010%\u001a\u00020\u0002HÆ\u0003¢\u0006\u0004\b%\u0010 J\u0010\u0010&\u001a\u00020\u0002HÆ\u0003¢\u0006\u0004\b&\u0010 J\u0010\u0010'\u001a\u00020\nHÆ\u0003¢\u0006\u0004\b'\u0010(J\u0010\u0010)\u001a\u00020\nHÆ\u0003¢\u0006\u0004\b)\u0010(J\u0010\u0010*\u001a\u00020\nHÆ\u0003¢\u0006\u0004\b*\u0010(J\u0010\u0010+\u001a\u00020\nHÆ\u0003¢\u0006\u0004\b+\u0010(J\u0010\u0010,\u001a\u00020\u000fHÆ\u0003¢\u0006\u0004\b,\u0010\u001eJ\u0010\u0010-\u001a\u00020\u0002HÆ\u0003¢\u0006\u0004\b-\u0010 J\u0010\u0010.\u001a\u00020\u0012HÆ\u0003¢\u0006\u0004\b.\u0010/J\u0092\u0001\u00100\u001a\u00020\u00002\b\b\u0002\u0010\u0003\u001a\u00020\u00022\b\b\u0002\u0010\u0005\u001a\u00020\u00042\b\b\u0002\u0010\u0006\u001a\u00020\u00042\b\b\u0002\u0010\u0007\u001a\u00020\u00022\b\b\u0002\u0010\b\u001a\u00020\u00022\b\b\u0002\u0010\t\u001a\u00020\u00022\b\b\u0002\u0010\u000b\u001a\u00020\n2\b\b\u0002\u0010\f\u001a\u00020\n2\b\b\u0002\u0010\r\u001a\u00020\n2\b\b\u0002\u0010\u000e\u001a\u00020\n2\b\b\u0002\u0010\u0010\u001a\u00020\u000f2\b\b\u0002\u0010\u0011\u001a\u00020\u00022\b\b\u0002\u0010\u0013\u001a\u00020\u0012HÆ\u0001¢\u0006\u0004\b0\u00101J\u0010\u00102\u001a\u00020\u0002HÖ\u0001¢\u0006\u0004\b2\u0010 J\u0010\u00103\u001a\u00020\u000fHÖ\u0001¢\u0006\u0004\b3\u0010\u001eJ\u001a\u00106\u001a\u00020\u00122\b\u00105\u001a\u0004\u0018\u000104HÖ\u0003¢\u0006\u0004\b6\u00107R\"\u0010\u0003\u001a\u00020\u00028\u0006@\u0006X\u0086\u000e¢\u0006\u0012\n\u0004\b\u0003\u00108\u001a\u0004\b9\u0010 \"\u0004\b:\u0010;R\"\u0010\u0005\u001a\u00020\u00048\u0006@\u0006X\u0086\u000e¢\u0006\u0012\n\u0004\b\u0005\u0010<\u001a\u0004\b=\u0010\"\"\u0004\b>\u0010?R\"\u0010\u0006\u001a\u00020\u00048\u0006@\u0006X\u0086\u000e¢\u0006\u0012\n\u0004\b\u0006\u0010<\u001a\u0004\b@\u0010\"\"\u0004\bA\u0010?R\"\u0010\u0007\u001a\u00020\u00028\u0006@\u0006X\u0086\u000e¢\u0006\u0012\n\u0004\b\u0007\u00108\u001a\u0004\bB\u0010 \"\u0004\bC\u0010;R\"\u0010\b\u001a\u00020\u00028\u0006@\u0006X\u0086\u000e¢\u0006\u0012\n\u0004\b\b\u00108\u001a\u0004\bD\u0010 \"\u0004\bE\u0010;R\"\u0010\t\u001a\u00020\u00028\u0006@\u0006X\u0086\u000e¢\u0006\u0012\n\u0004\b\t\u00108\u001a\u0004\bF\u0010 \"\u0004\bG\u0010;R\"\u0010\u000b\u001a\u00020\n8\u0006@\u0006X\u0086\u000e¢\u0006\u0012\n\u0004\b\u000b\u0010H\u001a\u0004\bI\u0010(\"\u0004\bJ\u0010KR\"\u0010\f\u001a\u00020\n8\u0006@\u0006X\u0086\u000e¢\u0006\u0012\n\u0004\b\f\u0010H\u001a\u0004\bL\u0010(\"\u0004\bM\u0010KR\"\u0010\r\u001a\u00020\n8\u0006@\u0006X\u0086\u000e¢\u0006\u0012\n\u0004\b\r\u0010H\u001a\u0004\bN\u0010(\"\u0004\bO\u0010KR\"\u0010\u000e\u001a\u00020\n8\u0006@\u0006X\u0086\u000e¢\u0006\u0012\n\u0004\b\u000e\u0010H\u001a\u0004\bP\u0010(\"\u0004\bQ\u0010KR\"\u0010\u0010\u001a\u00020\u000f8\u0006@\u0006X\u0086\u000e¢\u0006\u0012\n\u0004\b\u0010\u0010R\u001a\u0004\bS\u0010\u001e\"\u0004\bT\u0010UR\"\u0010\u0011\u001a\u00020\u00028\u0006@\u0006X\u0086\u000e¢\u0006\u0012\n\u0004\b\u0011\u00108\u001a\u0004\bV\u0010 \"\u0004\bW\u0010;R\"\u0010\u0013\u001a\u00020\u00128\u0006@\u0006X\u0086\u000e¢\u0006\u0012\n\u0004\b\u0013\u0010X\u001a\u0004\b\u0013\u0010/\"\u0004\bY\u0010Z¨\u0006]"}, d2 = {"Lsp/aicoin_kline/chart/data/AIWinRateItem;", "Landroid/os/Parcelable;", "", "id", "", "signal_time_s", "signal_time", "signal_type", "signal_price", "side", "", "capital_rate", "history_win_rate", "advise_win_rate", "advise_loss_rate", "", "state", "price", "", "isNew", "<init>", "(Ljava/lang/String;JJLjava/lang/String;Ljava/lang/String;Ljava/lang/String;DDDDILjava/lang/String;Z)V", "Landroid/os/Parcel;", "parcel", "(Landroid/os/Parcel;)V", "flags", "LQf/H;", "writeToParcel", "(Landroid/os/Parcel;I)V", "describeContents", "()I", "component1", "()Ljava/lang/String;", "component2", "()J", "component3", "component4", "component5", "component6", "component7", "()D", "component8", "component9", "component10", "component11", "component12", "component13", "()Z", "copy", "(Ljava/lang/String;JJLjava/lang/String;Ljava/lang/String;Ljava/lang/String;DDDDILjava/lang/String;Z)Lsp/aicoin_kline/chart/data/AIWinRateItem;", "toString", "hashCode", "", "other", "equals", "(Ljava/lang/Object;)Z", "Ljava/lang/String;", "getId", "setId", "(Ljava/lang/String;)V", "J", "getSignal_time_s", "setSignal_time_s", "(J)V", "getSignal_time", "setSignal_time", "getSignal_type", "setSignal_type", "getSignal_price", "setSignal_price", "getSide", "setSide", "D", "getCapital_rate", "setCapital_rate", "(D)V", "getHistory_win_rate", "setHistory_win_rate", "getAdvise_win_rate", "setAdvise_win_rate", "getAdvise_loss_rate", "setAdvise_loss_rate", "I", "getState", "setState", "(I)V", "getPrice", "setPrice", "Z", "setNew", "(Z)V", "CREATOR", am.av, "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class AIWinRateItem implements Parcelable {

    /* JADX INFO: renamed from: CREATOR, reason: from kotlin metadata */
    public static final Companion INSTANCE = new Companion(null);
    private double advise_loss_rate;
    private double advise_win_rate;
    private double capital_rate;
    private double history_win_rate;
    private String id;
    private boolean isNew;
    private String price;
    private String side;
    private String signal_price;
    private long signal_time;
    private long signal_time_s;
    private String signal_type;
    private int state;

    /* JADX INFO: renamed from: sp.aicoin_kline.chart.data.AIWinRateItem$a, reason: from kotlin metadata */
    public static final class Companion implements Parcelable.Creator {
        public Companion(DefaultConstructorMarker defaultConstructorMarker) {
        }

        @Override // android.os.Parcelable.Creator
        /* JADX INFO: renamed from: a, reason: merged with bridge method [inline-methods] */
        public AIWinRateItem createFromParcel(Parcel parcel) {
            return new AIWinRateItem(parcel);
        }

        @Override // android.os.Parcelable.Creator
        /* JADX INFO: renamed from: b, reason: merged with bridge method [inline-methods] */
        public AIWinRateItem[] newArray(int i10) {
            return new AIWinRateItem[i10];
        }
    }

    public AIWinRateItem() {
        this(null, 0L, 0L, null, null, null, 0.0d, 0.0d, 0.0d, 0.0d, 0, null, false, 8191, null);
    }

    /* JADX WARN: Illegal instructions before constructor call */
    public AIWinRateItem(Parcel parcel) {
        String string = parcel.readString();
        String str = string == null ? "" : string;
        long j10 = parcel.readLong();
        long j11 = parcel.readLong();
        String string2 = parcel.readString();
        String str2 = string2 == null ? "" : string2;
        String string3 = parcel.readString();
        String str3 = string3 == null ? "" : string3;
        String string4 = parcel.readString();
        String str4 = string4 == null ? "" : string4;
        double d10 = parcel.readDouble();
        double d11 = parcel.readDouble();
        double d12 = parcel.readDouble();
        double d13 = parcel.readDouble();
        int i10 = parcel.readInt();
        String string5 = parcel.readString();
        this(str, j10, j11, str2, str3, str4, d10, d11, d12, d13, i10, string5 == null ? "" : string5, false, 4096, null);
    }

    public AIWinRateItem(String str, long j10, long j11, String str2, String str3, String str4, double d10, double d11, double d12, double d13, int i10, String str5, boolean z10) {
        this.id = str;
        this.signal_time_s = j10;
        this.signal_time = j11;
        this.signal_type = str2;
        this.signal_price = str3;
        this.side = str4;
        this.capital_rate = d10;
        this.history_win_rate = d11;
        this.advise_win_rate = d12;
        this.advise_loss_rate = d13;
        this.state = i10;
        this.price = str5;
        this.isNew = z10;
    }

    public /* synthetic */ AIWinRateItem(String str, long j10, long j11, String str2, String str3, String str4, double d10, double d11, double d12, double d13, int i10, String str5, boolean z10, int i11, DefaultConstructorMarker defaultConstructorMarker) {
        this((i11 & 1) != 0 ? "" : str, (i11 & 2) != 0 ? 0L : j10, (i11 & 4) == 0 ? j11 : 0L, (i11 & 8) != 0 ? "" : str2, (i11 & 16) != 0 ? "" : str3, (i11 & 32) != 0 ? "" : str4, (i11 & 64) != 0 ? 0.0d : d10, (i11 & 128) != 0 ? 0.0d : d11, (i11 & 256) != 0 ? 0.0d : d12, (i11 & 512) == 0 ? d13 : 0.0d, (i11 & 1024) != 0 ? -1 : i10, (i11 & 2048) == 0 ? str5 : "", (i11 & 4096) != 0 ? false : z10);
    }

    public static /* synthetic */ AIWinRateItem copy$default(AIWinRateItem aIWinRateItem, String str, long j10, long j11, String str2, String str3, String str4, double d10, double d11, double d12, double d13, int i10, String str5, boolean z10, int i11, Object obj) {
        String str6 = (i11 & 1) != 0 ? aIWinRateItem.id : str;
        long j12 = (i11 & 2) != 0 ? aIWinRateItem.signal_time_s : j10;
        return aIWinRateItem.copy(str6, j12, (i11 & 4) != 0 ? aIWinRateItem.signal_time : j11, (i11 & 8) != 0 ? aIWinRateItem.signal_type : str2, (i11 & 16) != 0 ? aIWinRateItem.signal_price : str3, (i11 & 32) != 0 ? aIWinRateItem.side : str4, (i11 & 64) != 0 ? aIWinRateItem.capital_rate : d10, (i11 & 128) != 0 ? aIWinRateItem.history_win_rate : d11, (i11 & 256) != 0 ? aIWinRateItem.advise_win_rate : d12, (i11 & 512) != 0 ? aIWinRateItem.advise_loss_rate : d13, (i11 & 1024) != 0 ? aIWinRateItem.state : i10, (i11 & 2048) != 0 ? aIWinRateItem.price : str5, (i11 & 4096) != 0 ? aIWinRateItem.isNew : z10);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final String getId() {
        return this.id;
    }

    /* JADX INFO: renamed from: component10, reason: from getter */
    public final double getAdvise_loss_rate() {
        return this.advise_loss_rate;
    }

    /* JADX INFO: renamed from: component11, reason: from getter */
    public final int getState() {
        return this.state;
    }

    /* JADX INFO: renamed from: component12, reason: from getter */
    public final String getPrice() {
        return this.price;
    }

    /* JADX INFO: renamed from: component13, reason: from getter */
    public final boolean getIsNew() {
        return this.isNew;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final long getSignal_time_s() {
        return this.signal_time_s;
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    public final long getSignal_time() {
        return this.signal_time;
    }

    /* JADX INFO: renamed from: component4, reason: from getter */
    public final String getSignal_type() {
        return this.signal_type;
    }

    /* JADX INFO: renamed from: component5, reason: from getter */
    public final String getSignal_price() {
        return this.signal_price;
    }

    /* JADX INFO: renamed from: component6, reason: from getter */
    public final String getSide() {
        return this.side;
    }

    /* JADX INFO: renamed from: component7, reason: from getter */
    public final double getCapital_rate() {
        return this.capital_rate;
    }

    /* JADX INFO: renamed from: component8, reason: from getter */
    public final double getHistory_win_rate() {
        return this.history_win_rate;
    }

    /* JADX INFO: renamed from: component9, reason: from getter */
    public final double getAdvise_win_rate() {
        return this.advise_win_rate;
    }

    public final AIWinRateItem copy(String id2, long signal_time_s, long signal_time, String signal_type, String signal_price, String side, double capital_rate, double history_win_rate, double advise_win_rate, double advise_loss_rate, int state, String price, boolean isNew) {
        return new AIWinRateItem(id2, signal_time_s, signal_time, signal_type, signal_price, side, capital_rate, history_win_rate, advise_win_rate, advise_loss_rate, state, price, isNew);
    }

    @Override // android.os.Parcelable
    public int describeContents() {
        return 0;
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof AIWinRateItem)) {
            return false;
        }
        AIWinRateItem aIWinRateItem = (AIWinRateItem) other;
        return AbstractC7609s.f(this.id, aIWinRateItem.id) && this.signal_time_s == aIWinRateItem.signal_time_s && this.signal_time == aIWinRateItem.signal_time && AbstractC7609s.f(this.signal_type, aIWinRateItem.signal_type) && AbstractC7609s.f(this.signal_price, aIWinRateItem.signal_price) && AbstractC7609s.f(this.side, aIWinRateItem.side) && Double.compare(this.capital_rate, aIWinRateItem.capital_rate) == 0 && Double.compare(this.history_win_rate, aIWinRateItem.history_win_rate) == 0 && Double.compare(this.advise_win_rate, aIWinRateItem.advise_win_rate) == 0 && Double.compare(this.advise_loss_rate, aIWinRateItem.advise_loss_rate) == 0 && this.state == aIWinRateItem.state && AbstractC7609s.f(this.price, aIWinRateItem.price) && this.isNew == aIWinRateItem.isNew;
    }

    public final double getAdvise_loss_rate() {
        return this.advise_loss_rate;
    }

    public final double getAdvise_win_rate() {
        return this.advise_win_rate;
    }

    public final double getCapital_rate() {
        return this.capital_rate;
    }

    public final double getHistory_win_rate() {
        return this.history_win_rate;
    }

    public final String getId() {
        return this.id;
    }

    public final String getPrice() {
        return this.price;
    }

    public final String getSide() {
        return this.side;
    }

    public final String getSignal_price() {
        return this.signal_price;
    }

    public final long getSignal_time() {
        return this.signal_time;
    }

    public final long getSignal_time_s() {
        return this.signal_time_s;
    }

    public final String getSignal_type() {
        return this.signal_type;
    }

    public final int getState() {
        return this.state;
    }

    public int hashCode() {
        return Boolean.hashCode(this.isNew) + d.a(this.price, (Integer.hashCode(this.state) + ((Double.hashCode(this.advise_loss_rate) + ((Double.hashCode(this.advise_win_rate) + ((Double.hashCode(this.history_win_rate) + ((Double.hashCode(this.capital_rate) + d.a(this.side, d.a(this.signal_price, d.a(this.signal_type, (Long.hashCode(this.signal_time) + ((Long.hashCode(this.signal_time_s) + (this.id.hashCode() * 31)) * 31)) * 31, 31), 31), 31)) * 31)) * 31)) * 31)) * 31)) * 31, 31);
    }

    public final boolean isNew() {
        return this.isNew;
    }

    public final void setAdvise_loss_rate(double d10) {
        this.advise_loss_rate = d10;
    }

    public final void setAdvise_win_rate(double d10) {
        this.advise_win_rate = d10;
    }

    public final void setCapital_rate(double d10) {
        this.capital_rate = d10;
    }

    public final void setHistory_win_rate(double d10) {
        this.history_win_rate = d10;
    }

    public final void setId(String str) {
        this.id = str;
    }

    public final void setNew(boolean z10) {
        this.isNew = z10;
    }

    public final void setPrice(String str) {
        this.price = str;
    }

    public final void setSide(String str) {
        this.side = str;
    }

    public final void setSignal_price(String str) {
        this.signal_price = str;
    }

    public final void setSignal_time(long j10) {
        this.signal_time = j10;
    }

    public final void setSignal_time_s(long j10) {
        this.signal_time_s = j10;
    }

    public final void setSignal_type(String str) {
        this.signal_type = str;
    }

    public final void setState(int i10) {
        this.state = i10;
    }

    public String toString() {
        return "AIWinRateItem(id=" + this.id + ", signal_time_s=" + this.signal_time_s + ", signal_time=" + this.signal_time + ", signal_type=" + this.signal_type + ", signal_price=" + this.signal_price + ", side=" + this.side + ", capital_rate=" + this.capital_rate + ", history_win_rate=" + this.history_win_rate + ", advise_win_rate=" + this.advise_win_rate + ", advise_loss_rate=" + this.advise_loss_rate + ", state=" + this.state + ", price=" + this.price + ", isNew=" + this.isNew + ')';
    }

    @Override // android.os.Parcelable
    public void writeToParcel(Parcel parcel, int flags) {
        parcel.writeString(this.id);
        parcel.writeLong(this.signal_time_s);
        parcel.writeLong(this.signal_time);
        parcel.writeString(this.signal_type);
        parcel.writeString(this.signal_price);
        parcel.writeString(this.side);
        parcel.writeDouble(this.capital_rate);
        parcel.writeDouble(this.history_win_rate);
        parcel.writeDouble(this.advise_win_rate);
        parcel.writeDouble(this.advise_loss_rate);
        parcel.writeInt(this.state);
        parcel.writeString(this.price);
    }
}
