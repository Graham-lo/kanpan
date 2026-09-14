package sp.aicoin_kline.chart.data;

import androidx.annotation.Keep;
import kk.d;
import kk.h;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000\"\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0010\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0002\b\u0002\b\u0087\b\u0018\u00002\u00020\u0001B3\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\b\u0002\u0010\u0004\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0005\u001a\u00020\u0003\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0007\u0010\bJ\u000b\u0010\u000e\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\t\u0010\u000f\u001a\u00020\u0003HÆ\u0003J\t\u0010\u0010\u001a\u00020\u0003HÆ\u0003J\u000b\u0010\u0011\u001a\u0004\u0018\u00010\u0003HÆ\u0003J5\u0010\u0012\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\b\b\u0002\u0010\u0004\u001a\u00020\u00032\b\b\u0002\u0010\u0005\u001a\u00020\u00032\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\u0013\u001a\u00020\u00142\b\u0010\u0015\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0016\u001a\u00020\u0017HÖ\u0001J\t\u0010\u0018\u001a\u00020\u0003HÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\t\u0010\nR\u0011\u0010\u0004\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u000b\u0010\nR\u0011\u0010\u0005\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\f\u0010\nR\u0013\u0010\u0006\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\r\u0010\n¨\u0006\u0019"}, d2 = {"Lsp/aicoin_kline/chart/data/PresetOrder;", "", "order_amount", "", "order_type", "trade_type", "trade_unit", "<init>", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V", "getOrder_amount", "()Ljava/lang/String;", "getOrder_type", "getTrade_type", "getTrade_unit", "component1", "component2", "component3", "component4", "copy", "equals", "", "other", "hashCode", "", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class PresetOrder {
    private final String order_amount;
    private final String order_type;
    private final String trade_type;
    private final String trade_unit;

    public PresetOrder() {
        this(null, null, null, null, 15, null);
    }

    public PresetOrder(String str, String str2, String str3, String str4) {
        this.order_amount = str;
        this.order_type = str2;
        this.trade_type = str3;
        this.trade_unit = str4;
    }

    public /* synthetic */ PresetOrder(String str, String str2, String str3, String str4, int i10, DefaultConstructorMarker defaultConstructorMarker) {
        this((i10 & 1) != 0 ? "" : str, (i10 & 2) != 0 ? "" : str2, (i10 & 4) != 0 ? "" : str3, (i10 & 8) != 0 ? "" : str4);
    }

    public static /* synthetic */ PresetOrder copy$default(PresetOrder presetOrder, String str, String str2, String str3, String str4, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            str = presetOrder.order_amount;
        }
        if ((i10 & 2) != 0) {
            str2 = presetOrder.order_type;
        }
        if ((i10 & 4) != 0) {
            str3 = presetOrder.trade_type;
        }
        if ((i10 & 8) != 0) {
            str4 = presetOrder.trade_unit;
        }
        return presetOrder.copy(str, str2, str3, str4);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final String getOrder_amount() {
        return this.order_amount;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final String getOrder_type() {
        return this.order_type;
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    public final String getTrade_type() {
        return this.trade_type;
    }

    /* JADX INFO: renamed from: component4, reason: from getter */
    public final String getTrade_unit() {
        return this.trade_unit;
    }

    public final PresetOrder copy(String order_amount, String order_type, String trade_type, String trade_unit) {
        return new PresetOrder(order_amount, order_type, trade_type, trade_unit);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof PresetOrder)) {
            return false;
        }
        PresetOrder presetOrder = (PresetOrder) other;
        return AbstractC7609s.f(this.order_amount, presetOrder.order_amount) && AbstractC7609s.f(this.order_type, presetOrder.order_type) && AbstractC7609s.f(this.trade_type, presetOrder.trade_type) && AbstractC7609s.f(this.trade_unit, presetOrder.trade_unit);
    }

    public final String getOrder_amount() {
        return this.order_amount;
    }

    public final String getOrder_type() {
        return this.order_type;
    }

    public final String getTrade_type() {
        return this.trade_type;
    }

    public final String getTrade_unit() {
        return this.trade_unit;
    }

    public int hashCode() {
        String str = this.order_amount;
        int iA = d.a(this.trade_type, d.a(this.order_type, (str == null ? 0 : str.hashCode()) * 31, 31), 31);
        String str2 = this.trade_unit;
        return iA + (str2 != null ? str2.hashCode() : 0);
    }

    public String toString() {
        StringBuilder sb2 = new StringBuilder("PresetOrder(order_amount=");
        sb2.append(this.order_amount);
        sb2.append(", order_type=");
        sb2.append(this.order_type);
        sb2.append(", trade_type=");
        sb2.append(this.trade_type);
        sb2.append(", trade_unit=");
        return h.a(sb2, this.trade_unit, ')');
    }
}
