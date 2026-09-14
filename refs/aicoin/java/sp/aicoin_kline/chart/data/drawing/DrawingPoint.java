package sp.aicoin_kline.chart.data.drawing;

import androidx.annotation.Keep;
import com.umeng.analytics.pro.am;
import kotlin.Metadata;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000,\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\t\n\u0000\n\u0002\u0010\u0006\n\u0000\n\u0002\u0010\b\n\u0002\b\u0013\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0010\u000e\n\u0000\b\u0087\b\u0018\u00002\u00020\u0001B\u001f\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\u0006\u0010\u0004\u001a\u00020\u0005\u0012\u0006\u0010\u0006\u001a\u00020\u0007¢\u0006\u0004\b\b\u0010\tJ\t\u0010\u0016\u001a\u00020\u0003HÆ\u0003J\t\u0010\u0017\u001a\u00020\u0005HÆ\u0003J\t\u0010\u0018\u001a\u00020\u0007HÆ\u0003J'\u0010\u0019\u001a\u00020\u00002\b\b\u0002\u0010\u0002\u001a\u00020\u00032\b\b\u0002\u0010\u0004\u001a\u00020\u00052\b\b\u0002\u0010\u0006\u001a\u00020\u0007HÆ\u0001J\u0013\u0010\u001a\u001a\u00020\u001b2\b\u0010\u001c\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u001d\u001a\u00020\u0007HÖ\u0001J\t\u0010\u001e\u001a\u00020\u001fHÖ\u0001R\u001a\u0010\u0002\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\n\u0010\u000b\"\u0004\b\f\u0010\rR\u001a\u0010\u0004\u001a\u00020\u0005X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u000e\u0010\u000f\"\u0004\b\u0010\u0010\u0011R\u001a\u0010\u0006\u001a\u00020\u0007X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u0012\u0010\u0013\"\u0004\b\u0014\u0010\u0015¨\u0006 "}, d2 = {"Lsp/aicoin_kline/chart/data/drawing/DrawingPoint;", "", "x", "", "y", "", am.aB, "", "<init>", "(JDI)V", "getX", "()J", "setX", "(J)V", "getY", "()D", "setY", "(D)V", "getS", "()I", "setS", "(I)V", "component1", "component2", "component3", "copy", "equals", "", "other", "hashCode", "toString", "", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class DrawingPoint {
    private int s;
    private long x;
    private double y;

    public DrawingPoint(long j10, double d10, int i10) {
        this.x = j10;
        this.y = d10;
        this.s = i10;
    }

    public static /* synthetic */ DrawingPoint copy$default(DrawingPoint drawingPoint, long j10, double d10, int i10, int i11, Object obj) {
        if ((i11 & 1) != 0) {
            j10 = drawingPoint.x;
        }
        long j11 = j10;
        if ((i11 & 2) != 0) {
            d10 = drawingPoint.y;
        }
        double d11 = d10;
        if ((i11 & 4) != 0) {
            i10 = drawingPoint.s;
        }
        return drawingPoint.copy(j11, d11, i10);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final long getX() {
        return this.x;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final double getY() {
        return this.y;
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    public final int getS() {
        return this.s;
    }

    public final DrawingPoint copy(long x10, double y10, int s10) {
        return new DrawingPoint(x10, y10, s10);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof DrawingPoint)) {
            return false;
        }
        DrawingPoint drawingPoint = (DrawingPoint) other;
        return this.x == drawingPoint.x && Double.compare(this.y, drawingPoint.y) == 0 && this.s == drawingPoint.s;
    }

    public final int getS() {
        return this.s;
    }

    public final long getX() {
        return this.x;
    }

    public final double getY() {
        return this.y;
    }

    public int hashCode() {
        return Integer.hashCode(this.s) + ((Double.hashCode(this.y) + (Long.hashCode(this.x) * 31)) * 31);
    }

    public final void setS(int i10) {
        this.s = i10;
    }

    public final void setX(long j10) {
        this.x = j10;
    }

    public final void setY(double d10) {
        this.y = d10;
    }

    public String toString() {
        return "DrawingPoint(x=" + this.x + ", y=" + this.y + ", s=" + this.s + ')';
    }
}
