package sp.aicoin_kline.chart.data;

import androidx.annotation.Keep;
import kk.h;
import kotlin.Metadata;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000\"\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000e\n\u0002\b\n\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0002\b\u0002\b\u0087\b\u0018\u00002\u00020\u0001B\u0017\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\u0006\u0010\u0004\u001a\u00020\u0003¢\u0006\u0004\b\u0005\u0010\u0006J\t\u0010\n\u001a\u00020\u0003HÆ\u0003J\t\u0010\u000b\u001a\u00020\u0003HÆ\u0003J\u001d\u0010\f\u001a\u00020\u00002\b\b\u0002\u0010\u0002\u001a\u00020\u00032\b\b\u0002\u0010\u0004\u001a\u00020\u0003HÆ\u0001J\u0013\u0010\r\u001a\u00020\u000e2\b\u0010\u000f\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0010\u001a\u00020\u0011HÖ\u0001J\t\u0010\u0012\u001a\u00020\u0003HÖ\u0001R\u0011\u0010\u0002\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0007\u0010\bR\u0011\u0010\u0004\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\t\u0010\b¨\u0006\u0013"}, d2 = {"Lsp/aicoin_kline/chart/data/VpVrAlertItemData;", "", "price", "", "count", "<init>", "(Ljava/lang/String;Ljava/lang/String;)V", "getPrice", "()Ljava/lang/String;", "getCount", "component1", "component2", "copy", "equals", "", "other", "hashCode", "", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class VpVrAlertItemData {
    private final String count;
    private final String price;

    public VpVrAlertItemData(String str, String str2) {
        this.price = str;
        this.count = str2;
    }

    public static /* synthetic */ VpVrAlertItemData copy$default(VpVrAlertItemData vpVrAlertItemData, String str, String str2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            str = vpVrAlertItemData.price;
        }
        if ((i10 & 2) != 0) {
            str2 = vpVrAlertItemData.count;
        }
        return vpVrAlertItemData.copy(str, str2);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final String getPrice() {
        return this.price;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final String getCount() {
        return this.count;
    }

    public final VpVrAlertItemData copy(String price, String count) {
        return new VpVrAlertItemData(price, count);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof VpVrAlertItemData)) {
            return false;
        }
        VpVrAlertItemData vpVrAlertItemData = (VpVrAlertItemData) other;
        return AbstractC7609s.f(this.price, vpVrAlertItemData.price) && AbstractC7609s.f(this.count, vpVrAlertItemData.count);
    }

    public final String getCount() {
        return this.count;
    }

    public final String getPrice() {
        return this.price;
    }

    public int hashCode() {
        return this.count.hashCode() + (this.price.hashCode() * 31);
    }

    public String toString() {
        StringBuilder sb2 = new StringBuilder("VpVrAlertItemData(price=");
        sb2.append(this.price);
        sb2.append(", count=");
        return h.a(sb2, this.count, ')');
    }
}
