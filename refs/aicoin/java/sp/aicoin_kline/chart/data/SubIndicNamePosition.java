package sp.aicoin_kline.chart.data;

import androidx.annotation.Keep;
import kk.d;
import kk.h;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0002\b\u0002\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\u000b\n\u0002\b\u0019\b\u0087\b\u0018\u00002\u00020\u0001B3\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\u0006\u0010\u0004\u001a\u00020\u0003\u0012\u0006\u0010\u0005\u001a\u00020\u0006\u0012\b\b\u0002\u0010\u0007\u001a\u00020\b\u0012\b\b\u0002\u0010\t\u001a\u00020\u0006¢\u0006\u0004\b\n\u0010\u000bJ\t\u0010\u0017\u001a\u00020\u0003HÆ\u0003J\t\u0010\u0018\u001a\u00020\u0003HÆ\u0003J\t\u0010\u0019\u001a\u00020\u0006HÆ\u0003J\t\u0010\u001a\u001a\u00020\bHÆ\u0003J\t\u0010\u001b\u001a\u00020\u0006HÆ\u0003J;\u0010\u001c\u001a\u00020\u00002\b\b\u0002\u0010\u0002\u001a\u00020\u00032\b\b\u0002\u0010\u0004\u001a\u00020\u00032\b\b\u0002\u0010\u0005\u001a\u00020\u00062\b\b\u0002\u0010\u0007\u001a\u00020\b2\b\b\u0002\u0010\t\u001a\u00020\u0006HÆ\u0001J\u0013\u0010\u001d\u001a\u00020\b2\b\u0010\u001e\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u001f\u001a\u00020\u0003HÖ\u0001J\t\u0010 \u001a\u00020\u0006HÖ\u0001R\u0011\u0010\u0002\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\f\u0010\rR\u0011\u0010\u0004\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\rR\u0011\u0010\u0005\u001a\u00020\u0006¢\u0006\b\n\u0000\u001a\u0004\b\u000f\u0010\u0010R\u001a\u0010\u0007\u001a\u00020\bX\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u0007\u0010\u0011\"\u0004\b\u0012\u0010\u0013R\u001a\u0010\t\u001a\u00020\u0006X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u0014\u0010\u0010\"\u0004\b\u0015\u0010\u0016¨\u0006!"}, d2 = {"Lsp/aicoin_kline/chart/data/SubIndicNamePosition;", "", "x", "", "y", "key", "", "isScript", "", "title", "<init>", "(IILjava/lang/String;ZLjava/lang/String;)V", "getX", "()I", "getY", "getKey", "()Ljava/lang/String;", "()Z", "setScript", "(Z)V", "getTitle", "setTitle", "(Ljava/lang/String;)V", "component1", "component2", "component3", "component4", "component5", "copy", "equals", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class SubIndicNamePosition {
    private boolean isScript;
    private final String key;
    private String title;
    private final int x;
    private final int y;

    public SubIndicNamePosition(int i10, int i11, String str, boolean z10, String str2) {
        this.x = i10;
        this.y = i11;
        this.key = str;
        this.isScript = z10;
        this.title = str2;
    }

    public /* synthetic */ SubIndicNamePosition(int i10, int i11, String str, boolean z10, String str2, int i12, DefaultConstructorMarker defaultConstructorMarker) {
        this(i10, i11, str, (i12 & 8) != 0 ? false : z10, (i12 & 16) != 0 ? "" : str2);
    }

    public static /* synthetic */ SubIndicNamePosition copy$default(SubIndicNamePosition subIndicNamePosition, int i10, int i11, String str, boolean z10, String str2, int i12, Object obj) {
        if ((i12 & 1) != 0) {
            i10 = subIndicNamePosition.x;
        }
        if ((i12 & 2) != 0) {
            i11 = subIndicNamePosition.y;
        }
        if ((i12 & 4) != 0) {
            str = subIndicNamePosition.key;
        }
        if ((i12 & 8) != 0) {
            z10 = subIndicNamePosition.isScript;
        }
        if ((i12 & 16) != 0) {
            str2 = subIndicNamePosition.title;
        }
        String str3 = str2;
        String str4 = str;
        return subIndicNamePosition.copy(i10, i11, str4, z10, str3);
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

    /* JADX INFO: renamed from: component4, reason: from getter */
    public final boolean getIsScript() {
        return this.isScript;
    }

    /* JADX INFO: renamed from: component5, reason: from getter */
    public final String getTitle() {
        return this.title;
    }

    public final SubIndicNamePosition copy(int x10, int y10, String key, boolean isScript, String title) {
        return new SubIndicNamePosition(x10, y10, key, isScript, title);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof SubIndicNamePosition)) {
            return false;
        }
        SubIndicNamePosition subIndicNamePosition = (SubIndicNamePosition) other;
        return this.x == subIndicNamePosition.x && this.y == subIndicNamePosition.y && AbstractC7609s.f(this.key, subIndicNamePosition.key) && this.isScript == subIndicNamePosition.isScript && AbstractC7609s.f(this.title, subIndicNamePosition.title);
    }

    public final String getKey() {
        return this.key;
    }

    public final String getTitle() {
        return this.title;
    }

    public final int getX() {
        return this.x;
    }

    public final int getY() {
        return this.y;
    }

    public int hashCode() {
        return this.title.hashCode() + ((Boolean.hashCode(this.isScript) + d.a(this.key, (Integer.hashCode(this.y) + (Integer.hashCode(this.x) * 31)) * 31, 31)) * 31);
    }

    public final boolean isScript() {
        return this.isScript;
    }

    public final void setScript(boolean z10) {
        this.isScript = z10;
    }

    public final void setTitle(String str) {
        this.title = str;
    }

    public String toString() {
        StringBuilder sb2 = new StringBuilder("SubIndicNamePosition(x=");
        sb2.append(this.x);
        sb2.append(", y=");
        sb2.append(this.y);
        sb2.append(", key=");
        sb2.append(this.key);
        sb2.append(", isScript=");
        sb2.append(this.isScript);
        sb2.append(", title=");
        return h.a(sb2, this.title, ')');
    }
}
