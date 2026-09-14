package sp.aicoin_kline.chart.data;

import androidx.annotation.Keep;
import kk.d;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000\"\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0004\n\u0002\u0010\u000b\n\u0002\b\u0018\n\u0002\u0010\b\n\u0002\b\u0002\b\u0087\b\u0018\u00002\u00020\u0001B;\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\b\u0002\u0010\u0004\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0005\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0006\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0007\u001a\u00020\b¢\u0006\u0004\b\t\u0010\nJ\u000b\u0010\u0018\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\t\u0010\u0019\u001a\u00020\u0003HÆ\u0003J\t\u0010\u001a\u001a\u00020\u0003HÆ\u0003J\t\u0010\u001b\u001a\u00020\u0003HÆ\u0003J\t\u0010\u001c\u001a\u00020\bHÆ\u0003J=\u0010\u001d\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\b\b\u0002\u0010\u0004\u001a\u00020\u00032\b\b\u0002\u0010\u0005\u001a\u00020\u00032\b\b\u0002\u0010\u0006\u001a\u00020\u00032\b\b\u0002\u0010\u0007\u001a\u00020\bHÆ\u0001J\u0013\u0010\u001e\u001a\u00020\b2\b\u0010\u001f\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010 \u001a\u00020!HÖ\u0001J\t\u0010\"\u001a\u00020\u0003HÖ\u0001R\u001c\u0010\u0002\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u000b\u0010\f\"\u0004\b\r\u0010\u000eR\u001a\u0010\u0004\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u000f\u0010\f\"\u0004\b\u0010\u0010\u000eR\u001a\u0010\u0005\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u0011\u0010\f\"\u0004\b\u0012\u0010\u000eR\u001a\u0010\u0006\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u0013\u0010\f\"\u0004\b\u0014\u0010\u000eR\u001a\u0010\u0007\u001a\u00020\bX\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u0007\u0010\u0015\"\u0004\b\u0016\u0010\u0017¨\u0006#"}, d2 = {"Lsp/aicoin_kline/chart/data/AIHandleLineItem;", "", "price", "", "profit", "degree", "position", "isBids", "", "<init>", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Z)V", "getPrice", "()Ljava/lang/String;", "setPrice", "(Ljava/lang/String;)V", "getProfit", "setProfit", "getDegree", "setDegree", "getPosition", "setPosition", "()Z", "setBids", "(Z)V", "component1", "component2", "component3", "component4", "component5", "copy", "equals", "other", "hashCode", "", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class AIHandleLineItem {
    private String degree;
    private boolean isBids;
    private String position;
    private String price;
    private String profit;

    public AIHandleLineItem() {
        this(null, null, null, null, false, 31, null);
    }

    public AIHandleLineItem(String str, String str2, String str3, String str4, boolean z10) {
        this.price = str;
        this.profit = str2;
        this.degree = str3;
        this.position = str4;
        this.isBids = z10;
    }

    public /* synthetic */ AIHandleLineItem(String str, String str2, String str3, String str4, boolean z10, int i10, DefaultConstructorMarker defaultConstructorMarker) {
        this((i10 & 1) != 0 ? "" : str, (i10 & 2) != 0 ? "" : str2, (i10 & 4) != 0 ? "" : str3, (i10 & 8) != 0 ? "" : str4, (i10 & 16) != 0 ? false : z10);
    }

    public static /* synthetic */ AIHandleLineItem copy$default(AIHandleLineItem aIHandleLineItem, String str, String str2, String str3, String str4, boolean z10, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            str = aIHandleLineItem.price;
        }
        if ((i10 & 2) != 0) {
            str2 = aIHandleLineItem.profit;
        }
        if ((i10 & 4) != 0) {
            str3 = aIHandleLineItem.degree;
        }
        if ((i10 & 8) != 0) {
            str4 = aIHandleLineItem.position;
        }
        if ((i10 & 16) != 0) {
            z10 = aIHandleLineItem.isBids;
        }
        boolean z11 = z10;
        String str5 = str3;
        return aIHandleLineItem.copy(str, str2, str5, str4, z11);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final String getPrice() {
        return this.price;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final String getProfit() {
        return this.profit;
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    public final String getDegree() {
        return this.degree;
    }

    /* JADX INFO: renamed from: component4, reason: from getter */
    public final String getPosition() {
        return this.position;
    }

    /* JADX INFO: renamed from: component5, reason: from getter */
    public final boolean getIsBids() {
        return this.isBids;
    }

    public final AIHandleLineItem copy(String price, String profit, String degree, String position, boolean isBids) {
        return new AIHandleLineItem(price, profit, degree, position, isBids);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof AIHandleLineItem)) {
            return false;
        }
        AIHandleLineItem aIHandleLineItem = (AIHandleLineItem) other;
        return AbstractC7609s.f(this.price, aIHandleLineItem.price) && AbstractC7609s.f(this.profit, aIHandleLineItem.profit) && AbstractC7609s.f(this.degree, aIHandleLineItem.degree) && AbstractC7609s.f(this.position, aIHandleLineItem.position) && this.isBids == aIHandleLineItem.isBids;
    }

    public final String getDegree() {
        return this.degree;
    }

    public final String getPosition() {
        return this.position;
    }

    public final String getPrice() {
        return this.price;
    }

    public final String getProfit() {
        return this.profit;
    }

    public int hashCode() {
        String str = this.price;
        return Boolean.hashCode(this.isBids) + d.a(this.position, d.a(this.degree, d.a(this.profit, (str == null ? 0 : str.hashCode()) * 31, 31), 31), 31);
    }

    public final boolean isBids() {
        return this.isBids;
    }

    public final void setBids(boolean z10) {
        this.isBids = z10;
    }

    public final void setDegree(String str) {
        this.degree = str;
    }

    public final void setPosition(String str) {
        this.position = str;
    }

    public final void setPrice(String str) {
        this.price = str;
    }

    public final void setProfit(String str) {
        this.profit = str;
    }

    public String toString() {
        return "AIHandleLineItem(price=" + this.price + ", profit=" + this.profit + ", degree=" + this.degree + ", position=" + this.position + ", isBids=" + this.isBids + ')';
    }
}
