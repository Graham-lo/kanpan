package sp.aicoin_kline.chart.data;

import androidx.annotation.Keep;
import com.umeng.analytics.pro.am;
import kk.d;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000&\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\u0010\u0006\n\u0002\b\u0002\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\b\n\u0002\b\u000f\n\u0002\u0010\u000b\n\u0002\b\u0013\b\u0087\b\u0018\u0000 (2\u00020\u0001:\u0001)B/\u0012\b\b\u0002\u0010\u0003\u001a\u00020\u0002\u0012\b\b\u0002\u0010\u0004\u001a\u00020\u0002\u0012\b\b\u0002\u0010\u0006\u001a\u00020\u0005\u0012\b\b\u0002\u0010\b\u001a\u00020\u0007¢\u0006\u0004\b\t\u0010\nJ\u0010\u0010\u000b\u001a\u00020\u0002HÆ\u0003¢\u0006\u0004\b\u000b\u0010\fJ\u0010\u0010\r\u001a\u00020\u0002HÆ\u0003¢\u0006\u0004\b\r\u0010\fJ\u0010\u0010\u000e\u001a\u00020\u0005HÆ\u0003¢\u0006\u0004\b\u000e\u0010\u000fJ\u0010\u0010\u0010\u001a\u00020\u0007HÆ\u0003¢\u0006\u0004\b\u0010\u0010\u0011J8\u0010\u0012\u001a\u00020\u00002\b\b\u0002\u0010\u0003\u001a\u00020\u00022\b\b\u0002\u0010\u0004\u001a\u00020\u00022\b\b\u0002\u0010\u0006\u001a\u00020\u00052\b\b\u0002\u0010\b\u001a\u00020\u0007HÆ\u0001¢\u0006\u0004\b\u0012\u0010\u0013J\u0010\u0010\u0014\u001a\u00020\u0005HÖ\u0001¢\u0006\u0004\b\u0014\u0010\u000fJ\u0010\u0010\u0015\u001a\u00020\u0007HÖ\u0001¢\u0006\u0004\b\u0015\u0010\u0011J\u001a\u0010\u0018\u001a\u00020\u00172\b\u0010\u0016\u001a\u0004\u0018\u00010\u0001HÖ\u0003¢\u0006\u0004\b\u0018\u0010\u0019R\"\u0010\u0003\u001a\u00020\u00028\u0006@\u0006X\u0086\u000e¢\u0006\u0012\n\u0004\b\u0003\u0010\u001a\u001a\u0004\b\u001b\u0010\f\"\u0004\b\u001c\u0010\u001dR\"\u0010\u0004\u001a\u00020\u00028\u0006@\u0006X\u0086\u000e¢\u0006\u0012\n\u0004\b\u0004\u0010\u001a\u001a\u0004\b\u001e\u0010\f\"\u0004\b\u001f\u0010\u001dR\"\u0010\u0006\u001a\u00020\u00058\u0006@\u0006X\u0086\u000e¢\u0006\u0012\n\u0004\b\u0006\u0010 \u001a\u0004\b!\u0010\u000f\"\u0004\b\"\u0010#R\"\u0010\b\u001a\u00020\u00078\u0006@\u0006X\u0086\u000e¢\u0006\u0012\n\u0004\b\b\u0010$\u001a\u0004\b%\u0010\u0011\"\u0004\b&\u0010'¨\u0006*"}, d2 = {"Lsp/aicoin_kline/chart/data/AISRLItem;", "", "", "price", "amount", "", "side", "", "level", "<init>", "(DDLjava/lang/String;I)V", "component1", "()D", "component2", "component3", "()Ljava/lang/String;", "component4", "()I", "copy", "(DDLjava/lang/String;I)Lsp/aicoin_kline/chart/data/AISRLItem;", "toString", "hashCode", "other", "", "equals", "(Ljava/lang/Object;)Z", "D", "getPrice", "setPrice", "(D)V", "getAmount", "setAmount", "Ljava/lang/String;", "getSide", "setSide", "(Ljava/lang/String;)V", "I", "getLevel", "setLevel", "(I)V", "Companion", am.av, "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class AISRLItem {
    public static final String SIDE_PRESSURE = "pressure";
    public static final String SIDE_SUPPORT = "support";
    private double amount;
    private int level;
    private double price;
    private String side;

    public AISRLItem() {
        this(0.0d, 0.0d, null, 0, 15, null);
    }

    public AISRLItem(double d10, double d11, String str, int i10) {
        this.price = d10;
        this.amount = d11;
        this.side = str;
        this.level = i10;
    }

    public /* synthetic */ AISRLItem(double d10, double d11, String str, int i10, int i11, DefaultConstructorMarker defaultConstructorMarker) {
        this((i11 & 1) != 0 ? 0.0d : d10, (i11 & 2) != 0 ? 0.0d : d11, (i11 & 4) != 0 ? SIDE_PRESSURE : str, (i11 & 8) != 0 ? 0 : i10);
    }

    public static /* synthetic */ AISRLItem copy$default(AISRLItem aISRLItem, double d10, double d11, String str, int i10, int i11, Object obj) {
        if ((i11 & 1) != 0) {
            d10 = aISRLItem.price;
        }
        double d12 = d10;
        if ((i11 & 2) != 0) {
            d11 = aISRLItem.amount;
        }
        double d13 = d11;
        if ((i11 & 4) != 0) {
            str = aISRLItem.side;
        }
        String str2 = str;
        if ((i11 & 8) != 0) {
            i10 = aISRLItem.level;
        }
        return aISRLItem.copy(d12, d13, str2, i10);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final double getPrice() {
        return this.price;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final double getAmount() {
        return this.amount;
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    public final String getSide() {
        return this.side;
    }

    /* JADX INFO: renamed from: component4, reason: from getter */
    public final int getLevel() {
        return this.level;
    }

    public final AISRLItem copy(double price, double amount, String side, int level) {
        return new AISRLItem(price, amount, side, level);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof AISRLItem)) {
            return false;
        }
        AISRLItem aISRLItem = (AISRLItem) other;
        return Double.compare(this.price, aISRLItem.price) == 0 && Double.compare(this.amount, aISRLItem.amount) == 0 && AbstractC7609s.f(this.side, aISRLItem.side) && this.level == aISRLItem.level;
    }

    public final double getAmount() {
        return this.amount;
    }

    public final int getLevel() {
        return this.level;
    }

    public final double getPrice() {
        return this.price;
    }

    public final String getSide() {
        return this.side;
    }

    public int hashCode() {
        return Integer.hashCode(this.level) + d.a(this.side, (Double.hashCode(this.amount) + (Double.hashCode(this.price) * 31)) * 31, 31);
    }

    public final void setAmount(double d10) {
        this.amount = d10;
    }

    public final void setLevel(int i10) {
        this.level = i10;
    }

    public final void setPrice(double d10) {
        this.price = d10;
    }

    public final void setSide(String str) {
        this.side = str;
    }

    public String toString() {
        return "AISRLItem(price=" + this.price + ", amount=" + this.amount + ", side=" + this.side + ", level=" + this.level + ')';
    }
}
