package sp.aicoin_kline.chart.viewmodel;

import androidx.annotation.Keep;
import com.umeng.analytics.AnalyticsConfig;
import kk.a;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u00008\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u0006\n\u0002\b\u0002\n\u0002\u0010\u0007\n\u0002\b\u0002\n\u0002\u0010\t\n\u0002\b\u0002\n\u0002\u0010\b\n\u0002\b)\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0010\u000e\n\u0000\b\u0087\b\u0018\u00002\u00020\u0001Ba\u0012\b\b\u0002\u0010\u0002\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0004\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0005\u001a\u00020\u0006\u0012\b\b\u0002\u0010\u0007\u001a\u00020\u0006\u0012\b\b\u0002\u0010\b\u001a\u00020\t\u0012\b\b\u0002\u0010\n\u001a\u00020\t\u0012\b\b\u0002\u0010\u000b\u001a\u00020\f\u0012\b\b\u0002\u0010\r\u001a\u00020\f\u0012\b\b\u0002\u0010\u000e\u001a\u00020\u0006¢\u0006\u0004\b\u000f\u0010\u0010J\t\u0010+\u001a\u00020\u0003HÆ\u0003J\t\u0010,\u001a\u00020\u0003HÆ\u0003J\t\u0010-\u001a\u00020\u0006HÆ\u0003J\t\u0010.\u001a\u00020\u0006HÆ\u0003J\t\u0010/\u001a\u00020\tHÆ\u0003J\t\u00100\u001a\u00020\tHÆ\u0003J\t\u00101\u001a\u00020\fHÆ\u0003J\t\u00102\u001a\u00020\fHÆ\u0003J\t\u00103\u001a\u00020\u0006HÆ\u0003Jc\u00104\u001a\u00020\u00002\b\b\u0002\u0010\u0002\u001a\u00020\u00032\b\b\u0002\u0010\u0004\u001a\u00020\u00032\b\b\u0002\u0010\u0005\u001a\u00020\u00062\b\b\u0002\u0010\u0007\u001a\u00020\u00062\b\b\u0002\u0010\b\u001a\u00020\t2\b\b\u0002\u0010\n\u001a\u00020\t2\b\b\u0002\u0010\u000b\u001a\u00020\f2\b\b\u0002\u0010\r\u001a\u00020\f2\b\b\u0002\u0010\u000e\u001a\u00020\u0006HÆ\u0001J\u0013\u00105\u001a\u0002062\b\u00107\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u00108\u001a\u00020\fHÖ\u0001J\t\u00109\u001a\u00020:HÖ\u0001R\u001a\u0010\u0002\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u0011\u0010\u0012\"\u0004\b\u0013\u0010\u0014R\u001a\u0010\u0004\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u0015\u0010\u0012\"\u0004\b\u0016\u0010\u0014R\u001a\u0010\u0005\u001a\u00020\u0006X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u0017\u0010\u0018\"\u0004\b\u0019\u0010\u001aR\u001a\u0010\u0007\u001a\u00020\u0006X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u001b\u0010\u0018\"\u0004\b\u001c\u0010\u001aR\u001a\u0010\b\u001a\u00020\tX\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u001d\u0010\u001e\"\u0004\b\u001f\u0010 R\u001a\u0010\n\u001a\u00020\tX\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b!\u0010\u001e\"\u0004\b\"\u0010 R\u001a\u0010\u000b\u001a\u00020\fX\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b#\u0010$\"\u0004\b%\u0010&R\u001a\u0010\r\u001a\u00020\fX\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b'\u0010$\"\u0004\b(\u0010&R\u001a\u0010\u000e\u001a\u00020\u0006X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b)\u0010\u0018\"\u0004\b*\u0010\u001a¨\u0006;"}, d2 = {"Lsp/aicoin_kline/chart/viewmodel/OutSideIndicData;", "", "maxValue", "", "minValue", "maxValueY", "", "minValueY", AnalyticsConfig.RTD_START_TIME, "", "endTime", "startIndex", "", "endIndex", "windowStartOffset", "<init>", "(DDFFJJIIF)V", "getMaxValue", "()D", "setMaxValue", "(D)V", "getMinValue", "setMinValue", "getMaxValueY", "()F", "setMaxValueY", "(F)V", "getMinValueY", "setMinValueY", "getStartTime", "()J", "setStartTime", "(J)V", "getEndTime", "setEndTime", "getStartIndex", "()I", "setStartIndex", "(I)V", "getEndIndex", "setEndIndex", "getWindowStartOffset", "setWindowStartOffset", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "component9", "copy", "equals", "", "other", "hashCode", "toString", "", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class OutSideIndicData {
    private int endIndex;
    private long endTime;
    private double maxValue;
    private float maxValueY;
    private double minValue;
    private float minValueY;
    private int startIndex;
    private long startTime;
    private float windowStartOffset;

    public OutSideIndicData() {
        this(0.0d, 0.0d, 0.0f, 0.0f, 0L, 0L, 0, 0, 0.0f, 511, null);
    }

    public OutSideIndicData(double d10, double d11, float f10, float f11, long j10, long j11, int i10, int i11, float f12) {
        this.maxValue = d10;
        this.minValue = d11;
        this.maxValueY = f10;
        this.minValueY = f11;
        this.startTime = j10;
        this.endTime = j11;
        this.startIndex = i10;
        this.endIndex = i11;
        this.windowStartOffset = f12;
    }

    public /* synthetic */ OutSideIndicData(double d10, double d11, float f10, float f11, long j10, long j11, int i10, int i11, float f12, int i12, DefaultConstructorMarker defaultConstructorMarker) {
        this((i12 & 1) != 0 ? 0.0d : d10, (i12 & 2) == 0 ? d11 : 0.0d, (i12 & 4) != 0 ? 0.0f : f10, (i12 & 8) != 0 ? 0.0f : f11, (i12 & 16) != 0 ? 0L : j10, (i12 & 32) == 0 ? j11 : 0L, (i12 & 64) != 0 ? 0 : i10, (i12 & 128) == 0 ? i11 : 0, (i12 & 256) != 0 ? 0.0f : f12);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final double getMaxValue() {
        return this.maxValue;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final double getMinValue() {
        return this.minValue;
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    public final float getMaxValueY() {
        return this.maxValueY;
    }

    /* JADX INFO: renamed from: component4, reason: from getter */
    public final float getMinValueY() {
        return this.minValueY;
    }

    /* JADX INFO: renamed from: component5, reason: from getter */
    public final long getStartTime() {
        return this.startTime;
    }

    /* JADX INFO: renamed from: component6, reason: from getter */
    public final long getEndTime() {
        return this.endTime;
    }

    /* JADX INFO: renamed from: component7, reason: from getter */
    public final int getStartIndex() {
        return this.startIndex;
    }

    /* JADX INFO: renamed from: component8, reason: from getter */
    public final int getEndIndex() {
        return this.endIndex;
    }

    /* JADX INFO: renamed from: component9, reason: from getter */
    public final float getWindowStartOffset() {
        return this.windowStartOffset;
    }

    public final OutSideIndicData copy(double maxValue, double minValue, float maxValueY, float minValueY, long startTime, long endTime, int startIndex, int endIndex, float windowStartOffset) {
        return new OutSideIndicData(maxValue, minValue, maxValueY, minValueY, startTime, endTime, startIndex, endIndex, windowStartOffset);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof OutSideIndicData)) {
            return false;
        }
        OutSideIndicData outSideIndicData = (OutSideIndicData) other;
        return Double.compare(this.maxValue, outSideIndicData.maxValue) == 0 && Double.compare(this.minValue, outSideIndicData.minValue) == 0 && Float.compare(this.maxValueY, outSideIndicData.maxValueY) == 0 && Float.compare(this.minValueY, outSideIndicData.minValueY) == 0 && this.startTime == outSideIndicData.startTime && this.endTime == outSideIndicData.endTime && this.startIndex == outSideIndicData.startIndex && this.endIndex == outSideIndicData.endIndex && Float.compare(this.windowStartOffset, outSideIndicData.windowStartOffset) == 0;
    }

    public final int getEndIndex() {
        return this.endIndex;
    }

    public final long getEndTime() {
        return this.endTime;
    }

    public final double getMaxValue() {
        return this.maxValue;
    }

    public final float getMaxValueY() {
        return this.maxValueY;
    }

    public final double getMinValue() {
        return this.minValue;
    }

    public final float getMinValueY() {
        return this.minValueY;
    }

    public final int getStartIndex() {
        return this.startIndex;
    }

    public final long getStartTime() {
        return this.startTime;
    }

    public final float getWindowStartOffset() {
        return this.windowStartOffset;
    }

    public int hashCode() {
        return Float.hashCode(this.windowStartOffset) + ((Integer.hashCode(this.endIndex) + ((Integer.hashCode(this.startIndex) + ((Long.hashCode(this.endTime) + ((Long.hashCode(this.startTime) + a.a(this.minValueY, a.a(this.maxValueY, (Double.hashCode(this.minValue) + (Double.hashCode(this.maxValue) * 31)) * 31, 31), 31)) * 31)) * 31)) * 31)) * 31);
    }

    public final void setEndIndex(int i10) {
        this.endIndex = i10;
    }

    public final void setEndTime(long j10) {
        this.endTime = j10;
    }

    public final void setMaxValue(double d10) {
        this.maxValue = d10;
    }

    public final void setMaxValueY(float f10) {
        this.maxValueY = f10;
    }

    public final void setMinValue(double d10) {
        this.minValue = d10;
    }

    public final void setMinValueY(float f10) {
        this.minValueY = f10;
    }

    public final void setStartIndex(int i10) {
        this.startIndex = i10;
    }

    public final void setStartTime(long j10) {
        this.startTime = j10;
    }

    public final void setWindowStartOffset(float f10) {
        this.windowStartOffset = f10;
    }

    public String toString() {
        return "OutSideIndicData(maxValue=" + this.maxValue + ", minValue=" + this.minValue + ", maxValueY=" + this.maxValueY + ", minValueY=" + this.minValueY + ", startTime=" + this.startTime + ", endTime=" + this.endTime + ", startIndex=" + this.startIndex + ", endIndex=" + this.endIndex + ", windowStartOffset=" + this.windowStartOffset + ')';
    }
}
