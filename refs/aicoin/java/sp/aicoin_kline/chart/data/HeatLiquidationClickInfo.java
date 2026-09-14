package sp.aicoin_kline.chart.data;

import androidx.annotation.Keep;
import java.util.List;
import kotlin.Metadata;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000&\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0002\b\u0002\n\u0002\u0010 \n\u0002\u0010\u000e\n\u0002\b\f\n\u0002\u0010\u000b\n\u0002\b\u0004\b\u0087\b\u0018\u00002\u00020\u0001B%\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\u0006\u0010\u0004\u001a\u00020\u0003\u0012\f\u0010\u0005\u001a\b\u0012\u0004\u0012\u00020\u00070\u0006¢\u0006\u0004\b\b\u0010\tJ\t\u0010\u000f\u001a\u00020\u0003HÆ\u0003J\t\u0010\u0010\u001a\u00020\u0003HÆ\u0003J\u000f\u0010\u0011\u001a\b\u0012\u0004\u0012\u00020\u00070\u0006HÆ\u0003J-\u0010\u0012\u001a\u00020\u00002\b\b\u0002\u0010\u0002\u001a\u00020\u00032\b\b\u0002\u0010\u0004\u001a\u00020\u00032\u000e\b\u0002\u0010\u0005\u001a\b\u0012\u0004\u0012\u00020\u00070\u0006HÆ\u0001J\u0013\u0010\u0013\u001a\u00020\u00142\b\u0010\u0015\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0016\u001a\u00020\u0003HÖ\u0001J\t\u0010\u0017\u001a\u00020\u0007HÖ\u0001R\u0011\u0010\u0002\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\n\u0010\u000bR\u0011\u0010\u0004\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\f\u0010\u000bR\u0017\u0010\u0005\u001a\b\u0012\u0004\u0012\u00020\u00070\u0006¢\u0006\b\n\u0000\u001a\u0004\b\r\u0010\u000e¨\u0006\u0018"}, d2 = {"Lsp/aicoin_kline/chart/data/HeatLiquidationClickInfo;", "", "x", "", "y", "turnoverGrid", "", "", "<init>", "(IILjava/util/List;)V", "getX", "()I", "getY", "getTurnoverGrid", "()Ljava/util/List;", "component1", "component2", "component3", "copy", "equals", "", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class HeatLiquidationClickInfo {
    private final List<String> turnoverGrid;
    private final int x;
    private final int y;

    public HeatLiquidationClickInfo(int i10, int i11, List<String> list) {
        this.x = i10;
        this.y = i11;
        this.turnoverGrid = list;
    }

    /* JADX WARN: Multi-variable type inference failed */
    public static /* synthetic */ HeatLiquidationClickInfo copy$default(HeatLiquidationClickInfo heatLiquidationClickInfo, int i10, int i11, List list, int i12, Object obj) {
        if ((i12 & 1) != 0) {
            i10 = heatLiquidationClickInfo.x;
        }
        if ((i12 & 2) != 0) {
            i11 = heatLiquidationClickInfo.y;
        }
        if ((i12 & 4) != 0) {
            list = heatLiquidationClickInfo.turnoverGrid;
        }
        return heatLiquidationClickInfo.copy(i10, i11, list);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final int getX() {
        return this.x;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final int getY() {
        return this.y;
    }

    public final List<String> component3() {
        return this.turnoverGrid;
    }

    public final HeatLiquidationClickInfo copy(int x10, int y10, List<String> turnoverGrid) {
        return new HeatLiquidationClickInfo(x10, y10, turnoverGrid);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof HeatLiquidationClickInfo)) {
            return false;
        }
        HeatLiquidationClickInfo heatLiquidationClickInfo = (HeatLiquidationClickInfo) other;
        return this.x == heatLiquidationClickInfo.x && this.y == heatLiquidationClickInfo.y && AbstractC7609s.f(this.turnoverGrid, heatLiquidationClickInfo.turnoverGrid);
    }

    public final List<String> getTurnoverGrid() {
        return this.turnoverGrid;
    }

    public final int getX() {
        return this.x;
    }

    public final int getY() {
        return this.y;
    }

    public int hashCode() {
        return this.turnoverGrid.hashCode() + ((Integer.hashCode(this.y) + (Integer.hashCode(this.x) * 31)) * 31);
    }

    public String toString() {
        return "HeatLiquidationClickInfo(x=" + this.x + ", y=" + this.y + ", turnoverGrid=" + this.turnoverGrid + ')';
    }
}
