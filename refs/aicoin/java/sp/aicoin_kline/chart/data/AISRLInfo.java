package sp.aicoin_kline.chart.data;

import androidx.annotation.Keep;
import kk.d;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;
import p254m.aicoin.kline.main.MainKlineFragment;
import p292ng.i;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u00006\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\u0010\u0006\n\u0002\b\u0002\n\u0002\u0010\u000e\n\u0002\b\u0002\n\u0002\u0010\b\n\u0002\b\u0005\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0012\n\u0002\u0010\u000b\n\u0002\b\u0017\b\u0087\b\u0018\u00002\u00020\u0001BM\u0012\b\b\u0002\u0010\u0003\u001a\u00020\u0002\u0012\b\b\u0002\u0010\u0004\u001a\u00020\u0002\u0012\b\b\u0002\u0010\u0006\u001a\u00020\u0005\u0012\b\b\u0002\u0010\u0007\u001a\u00020\u0005\u0012\b\b\u0002\u0010\t\u001a\u00020\b\u0012\b\b\u0002\u0010\n\u001a\u00020\b\u0012\b\b\u0002\u0010\u000b\u001a\u00020\b¢\u0006\u0004\b\f\u0010\rJ/\u0010\u0011\u001a\u00020\u00102\u0006\u0010\u000f\u001a\u00020\u000e2\u0006\u0010\n\u001a\u00020\b2\u0006\u0010\u000b\u001a\u00020\b2\b\b\u0002\u0010\u0006\u001a\u00020\u0005¢\u0006\u0004\b\u0011\u0010\u0012J\r\u0010\u0013\u001a\u00020\u0005¢\u0006\u0004\b\u0013\u0010\u0014J\u0010\u0010\u0015\u001a\u00020\u0002HÆ\u0003¢\u0006\u0004\b\u0015\u0010\u0016J\u0010\u0010\u0017\u001a\u00020\u0002HÆ\u0003¢\u0006\u0004\b\u0017\u0010\u0016J\u0010\u0010\u0018\u001a\u00020\u0005HÆ\u0003¢\u0006\u0004\b\u0018\u0010\u0014J\u0010\u0010\u0019\u001a\u00020\u0005HÆ\u0003¢\u0006\u0004\b\u0019\u0010\u0014J\u0010\u0010\u001a\u001a\u00020\bHÆ\u0003¢\u0006\u0004\b\u001a\u0010\u001bJ\u0010\u0010\u001c\u001a\u00020\bHÆ\u0003¢\u0006\u0004\b\u001c\u0010\u001bJ\u0010\u0010\u001d\u001a\u00020\bHÆ\u0003¢\u0006\u0004\b\u001d\u0010\u001bJV\u0010\u001e\u001a\u00020\u00002\b\b\u0002\u0010\u0003\u001a\u00020\u00022\b\b\u0002\u0010\u0004\u001a\u00020\u00022\b\b\u0002\u0010\u0006\u001a\u00020\u00052\b\b\u0002\u0010\u0007\u001a\u00020\u00052\b\b\u0002\u0010\t\u001a\u00020\b2\b\b\u0002\u0010\n\u001a\u00020\b2\b\b\u0002\u0010\u000b\u001a\u00020\bHÆ\u0001¢\u0006\u0004\b\u001e\u0010\u001fJ\u0010\u0010 \u001a\u00020\u0005HÖ\u0001¢\u0006\u0004\b \u0010\u0014J\u0010\u0010!\u001a\u00020\bHÖ\u0001¢\u0006\u0004\b!\u0010\u001bJ\u001a\u0010$\u001a\u00020#2\b\u0010\"\u001a\u0004\u0018\u00010\u0001HÖ\u0003¢\u0006\u0004\b$\u0010%R\"\u0010\u0003\u001a\u00020\u00028\u0006@\u0006X\u0086\u000e¢\u0006\u0012\n\u0004\b\u0003\u0010&\u001a\u0004\b'\u0010\u0016\"\u0004\b(\u0010)R\"\u0010\u0004\u001a\u00020\u00028\u0006@\u0006X\u0086\u000e¢\u0006\u0012\n\u0004\b\u0004\u0010&\u001a\u0004\b*\u0010\u0016\"\u0004\b+\u0010)R\"\u0010\u0006\u001a\u00020\u00058\u0006@\u0006X\u0086\u000e¢\u0006\u0012\n\u0004\b\u0006\u0010,\u001a\u0004\b-\u0010\u0014\"\u0004\b.\u0010/R\"\u0010\u0007\u001a\u00020\u00058\u0006@\u0006X\u0086\u000e¢\u0006\u0012\n\u0004\b\u0007\u0010,\u001a\u0004\b0\u0010\u0014\"\u0004\b1\u0010/R\"\u0010\t\u001a\u00020\b8\u0006@\u0006X\u0086\u000e¢\u0006\u0012\n\u0004\b\t\u00102\u001a\u0004\b3\u0010\u001b\"\u0004\b4\u00105R\"\u0010\n\u001a\u00020\b8\u0006@\u0006X\u0086\u000e¢\u0006\u0012\n\u0004\b\n\u00102\u001a\u0004\b6\u0010\u001b\"\u0004\b7\u00105R\"\u0010\u000b\u001a\u00020\b8\u0006@\u0006X\u0086\u000e¢\u0006\u0012\n\u0004\b\u000b\u00102\u001a\u0004\b8\u0010\u001b\"\u0004\b9\u00105¨\u0006:"}, d2 = {"Lsp/aicoin_kline/chart/data/AISRLInfo;", "", "", "price", "amount", "", MainKlineFragment.FIELD_AISRL_AMOUNT_UNIT, "side", "", "level", "x", "y", "<init>", "(DDLjava/lang/String;Ljava/lang/String;III)V", "Lsp/aicoin_kline/chart/data/AISRLItem;", "aisrlItem", "LQf/H;", "initInfo", "(Lsp/aicoin_kline/chart/data/AISRLItem;IILjava/lang/String;)V", "displayTitle", "()Ljava/lang/String;", "component1", "()D", "component2", "component3", "component4", "component5", "()I", "component6", "component7", "copy", "(DDLjava/lang/String;Ljava/lang/String;III)Lsp/aicoin_kline/chart/data/AISRLInfo;", "toString", "hashCode", "other", "", "equals", "(Ljava/lang/Object;)Z", "D", "getPrice", "setPrice", "(D)V", "getAmount", "setAmount", "Ljava/lang/String;", "getAmountUnit", MainKlineFragment.METHOD_SET_AISRL_AMOUNT_UNIT, "(Ljava/lang/String;)V", "getSide", "setSide", "I", "getLevel", "setLevel", "(I)V", "getX", "setX", "getY", "setY", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class AISRLInfo {
    private double amount;
    private String amountUnit;
    private int level;
    private double price;
    private String side;
    private int x;
    private int y;

    public AISRLInfo() {
        this(0.0d, 0.0d, null, null, 0, 0, 0, 127, null);
    }

    public AISRLInfo(double d10, double d11, String str, String str2, int i10, int i11, int i12) {
        this.price = d10;
        this.amount = d11;
        this.amountUnit = str;
        this.side = str2;
        this.level = i10;
        this.x = i11;
        this.y = i12;
    }

    public /* synthetic */ AISRLInfo(double d10, double d11, String str, String str2, int i10, int i11, int i12, int i13, DefaultConstructorMarker defaultConstructorMarker) {
        this((i13 & 1) != 0 ? 0.0d : d10, (i13 & 2) != 0 ? 0.0d : d11, (i13 & 4) != 0 ? "" : str, (i13 & 8) != 0 ? AISRLItem.SIDE_PRESSURE : str2, (i13 & 16) != 0 ? 0 : i10, (i13 & 32) != 0 ? 0 : i11, (i13 & 64) != 0 ? 0 : i12);
    }

    public static /* synthetic */ AISRLInfo copy$default(AISRLInfo aISRLInfo, double d10, double d11, String str, String str2, int i10, int i11, int i12, int i13, Object obj) {
        if ((i13 & 1) != 0) {
            d10 = aISRLInfo.price;
        }
        double d12 = d10;
        if ((i13 & 2) != 0) {
            d11 = aISRLInfo.amount;
        }
        double d13 = d11;
        if ((i13 & 4) != 0) {
            str = aISRLInfo.amountUnit;
        }
        return aISRLInfo.copy(d12, d13, str, (i13 & 8) != 0 ? aISRLInfo.side : str2, (i13 & 16) != 0 ? aISRLInfo.level : i10, (i13 & 32) != 0 ? aISRLInfo.x : i11, (i13 & 64) != 0 ? aISRLInfo.y : i12);
    }

    public static /* synthetic */ void initInfo$default(AISRLInfo aISRLInfo, AISRLItem aISRLItem, int i10, int i11, String str, int i12, Object obj) {
        if ((i12 & 8) != 0) {
            str = "";
        }
        aISRLInfo.initInfo(aISRLItem, i10, i11, str);
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
    public final String getAmountUnit() {
        return this.amountUnit;
    }

    /* JADX INFO: renamed from: component4, reason: from getter */
    public final String getSide() {
        return this.side;
    }

    /* JADX INFO: renamed from: component5, reason: from getter */
    public final int getLevel() {
        return this.level;
    }

    /* JADX INFO: renamed from: component6, reason: from getter */
    public final int getX() {
        return this.x;
    }

    /* JADX INFO: renamed from: component7, reason: from getter */
    public final int getY() {
        return this.y;
    }

    public final AISRLInfo copy(double price, double amount, String amountUnit, String side, int level, int x10, int y10) {
        return new AISRLInfo(price, amount, amountUnit, side, level, x10, y10);
    }

    public final String displayTitle() {
        int iF = i.f(this.level, 1);
        if (AbstractC7609s.f(this.side, AISRLItem.SIDE_SUPPORT)) {
            return "支撑位" + iF;
        }
        return "压力位" + iF;
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof AISRLInfo)) {
            return false;
        }
        AISRLInfo aISRLInfo = (AISRLInfo) other;
        return Double.compare(this.price, aISRLInfo.price) == 0 && Double.compare(this.amount, aISRLInfo.amount) == 0 && AbstractC7609s.f(this.amountUnit, aISRLInfo.amountUnit) && AbstractC7609s.f(this.side, aISRLInfo.side) && this.level == aISRLInfo.level && this.x == aISRLInfo.x && this.y == aISRLInfo.y;
    }

    public final double getAmount() {
        return this.amount;
    }

    public final String getAmountUnit() {
        return this.amountUnit;
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

    public final int getX() {
        return this.x;
    }

    public final int getY() {
        return this.y;
    }

    public int hashCode() {
        return Integer.hashCode(this.y) + ((Integer.hashCode(this.x) + ((Integer.hashCode(this.level) + d.a(this.side, d.a(this.amountUnit, (Double.hashCode(this.amount) + (Double.hashCode(this.price) * 31)) * 31, 31), 31)) * 31)) * 31);
    }

    public final void initInfo(AISRLItem aisrlItem, int x10, int y10, String amountUnit) {
        this.price = aisrlItem.getPrice();
        this.amount = aisrlItem.getAmount();
        this.amountUnit = amountUnit;
        this.side = aisrlItem.getSide();
        this.level = aisrlItem.getLevel();
        this.x = x10;
        this.y = y10;
    }

    public final void setAmount(double d10) {
        this.amount = d10;
    }

    public final void setAmountUnit(String str) {
        this.amountUnit = str;
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

    public final void setX(int i10) {
        this.x = i10;
    }

    public final void setY(int i10) {
        this.y = i10;
    }

    public String toString() {
        return "AISRLInfo(price=" + this.price + ", amount=" + this.amount + ", amountUnit=" + this.amountUnit + ", side=" + this.side + ", level=" + this.level + ", x=" + this.x + ", y=" + this.y + ')';
    }
}
