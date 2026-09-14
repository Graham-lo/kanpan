package sp.aicoin_kline.chart.data;

import androidx.annotation.Keep;
import java.util.List;
import java.util.Map;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000&\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010 \n\u0002\u0010%\n\u0002\u0010\u000e\n\u0002\u0010\u0006\n\u0002\b\u0003\n\u0002\u0010\u0007\n\u0002\b\u0014\b\u0007\u0018\u00002\u00020\u0001BI\u0012\u0018\u0010\u0002\u001a\u0014\u0012\u0010\u0012\u000e\u0012\u0004\u0012\u00020\u0005\u0012\u0004\u0012\u00020\u00060\u00040\u0003\u0012\b\b\u0002\u0010\u0007\u001a\u00020\u0006\u0012\b\b\u0002\u0010\b\u001a\u00020\u0006\u0012\b\b\u0002\u0010\t\u001a\u00020\n\u0012\b\b\u0002\u0010\u000b\u001a\u00020\n¢\u0006\u0004\b\f\u0010\rR,\u0010\u0002\u001a\u0014\u0012\u0010\u0012\u000e\u0012\u0004\u0012\u00020\u0005\u0012\u0004\u0012\u00020\u00060\u00040\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u000e\u0010\u000f\"\u0004\b\u0010\u0010\u0011R\u001a\u0010\u0007\u001a\u00020\u0006X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u0012\u0010\u0013\"\u0004\b\u0014\u0010\u0015R\u001a\u0010\b\u001a\u00020\u0006X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u0016\u0010\u0013\"\u0004\b\u0017\u0010\u0015R\u001a\u0010\t\u001a\u00020\nX\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u0018\u0010\u0019\"\u0004\b\u001a\u0010\u001bR\u001a\u0010\u000b\u001a\u00020\nX\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u001c\u0010\u0019\"\u0004\b\u001d\u0010\u001b¨\u0006\u001e"}, d2 = {"Lsp/aicoin_kline/chart/data/AICYQItem;", "", "dataList", "", "", "", "", "maxValue", "minValue", "maxY", "", "minY", "<init>", "(Ljava/util/List;DDFF)V", "getDataList", "()Ljava/util/List;", "setDataList", "(Ljava/util/List;)V", "getMaxValue", "()D", "setMaxValue", "(D)V", "getMinValue", "setMinValue", "getMaxY", "()F", "setMaxY", "(F)V", "getMinY", "setMinY", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final class AICYQItem {
    private List<? extends Map<String, Double>> dataList;
    private double maxValue;
    private float maxY;
    private double minValue;
    private float minY;

    public AICYQItem(List<? extends Map<String, Double>> list, double d10, double d11, float f10, float f11) {
        this.dataList = list;
        this.maxValue = d10;
        this.minValue = d11;
        this.maxY = f10;
        this.minY = f11;
    }

    public /* synthetic */ AICYQItem(List list, double d10, double d11, float f10, float f11, int i10, DefaultConstructorMarker defaultConstructorMarker) {
        this(list, (i10 & 2) != 0 ? 1345.0d : d10, (i10 & 4) != 0 ? 1242.0d : d11, (i10 & 8) != 0 ? 535.0f : f10, (i10 & 16) != 0 ? 80.0f : f11);
    }

    public final List<Map<String, Double>> getDataList() {
        return this.dataList;
    }

    public final double getMaxValue() {
        return this.maxValue;
    }

    public final float getMaxY() {
        return this.maxY;
    }

    public final double getMinValue() {
        return this.minValue;
    }

    public final float getMinY() {
        return this.minY;
    }

    public final void setDataList(List<? extends Map<String, Double>> list) {
        this.dataList = list;
    }

    public final void setMaxValue(double d10) {
        this.maxValue = d10;
    }

    public final void setMaxY(float f10) {
        this.maxY = f10;
    }

    public final void setMinValue(double d10) {
        this.minValue = d10;
    }

    public final void setMinY(float f10) {
        this.minY = f10;
    }
}
