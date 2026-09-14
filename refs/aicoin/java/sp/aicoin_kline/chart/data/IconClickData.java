package sp.aicoin_kline.chart.data;

import androidx.annotation.Keep;
import kk.h;
import kotlin.Metadata;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000\"\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0002\b\u0002\n\u0002\u0010\u000e\n\u0002\b\f\n\u0002\u0010\u000b\n\u0002\b\u0004\b\u0087\b\u0018\u00002\u00020\u0001B\u001f\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\u0006\u0010\u0004\u001a\u00020\u0003\u0012\u0006\u0010\u0005\u001a\u00020\u0006¢\u0006\u0004\b\u0007\u0010\bJ\t\u0010\u000e\u001a\u00020\u0003HÆ\u0003J\t\u0010\u000f\u001a\u00020\u0003HÆ\u0003J\t\u0010\u0010\u001a\u00020\u0006HÆ\u0003J'\u0010\u0011\u001a\u00020\u00002\b\b\u0002\u0010\u0002\u001a\u00020\u00032\b\b\u0002\u0010\u0004\u001a\u00020\u00032\b\b\u0002\u0010\u0005\u001a\u00020\u0006HÆ\u0001J\u0013\u0010\u0012\u001a\u00020\u00132\b\u0010\u0014\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0015\u001a\u00020\u0003HÖ\u0001J\t\u0010\u0016\u001a\u00020\u0006HÖ\u0001R\u0011\u0010\u0002\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\t\u0010\nR\u0011\u0010\u0004\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u000b\u0010\nR\u0011\u0010\u0005\u001a\u00020\u0006¢\u0006\b\n\u0000\u001a\u0004\b\f\u0010\r¨\u0006\u0017"}, d2 = {"Lsp/aicoin_kline/chart/data/IconClickData;", "", "x", "", "y", "key", "", "<init>", "(IILjava/lang/String;)V", "getX", "()I", "getY", "getKey", "()Ljava/lang/String;", "component1", "component2", "component3", "copy", "equals", "", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class IconClickData {
    private final String key;
    private final int x;
    private final int y;

    public IconClickData(int i10, int i11, String str) {
        this.x = i10;
        this.y = i11;
        this.key = str;
    }

    public static /* synthetic */ IconClickData copy$default(IconClickData iconClickData, int i10, int i11, String str, int i12, Object obj) {
        if ((i12 & 1) != 0) {
            i10 = iconClickData.x;
        }
        if ((i12 & 2) != 0) {
            i11 = iconClickData.y;
        }
        if ((i12 & 4) != 0) {
            str = iconClickData.key;
        }
        return iconClickData.copy(i10, i11, str);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final int getX() {
        return this.x;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final int getY() {
        return this.y;
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    public final String getKey() {
        return this.key;
    }

    public final IconClickData copy(int x10, int y10, String key) {
        return new IconClickData(x10, y10, key);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof IconClickData)) {
            return false;
        }
        IconClickData iconClickData = (IconClickData) other;
        return this.x == iconClickData.x && this.y == iconClickData.y && AbstractC7609s.f(this.key, iconClickData.key);
    }

    public final String getKey() {
        return this.key;
    }

    public final int getX() {
        return this.x;
    }

    public final int getY() {
        return this.y;
    }

    public int hashCode() {
        return this.key.hashCode() + ((Integer.hashCode(this.y) + (Integer.hashCode(this.x) * 31)) * 31);
    }

    public String toString() {
        StringBuilder sb2 = new StringBuilder("IconClickData(x=");
        sb2.append(this.x);
        sb2.append(", y=");
        sb2.append(this.y);
        sb2.append(", key=");
        return h.a(sb2, this.key, ')');
    }
}
