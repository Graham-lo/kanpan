package sp.aicoin_kline.chart.data;

import Ah.x;
import androidx.annotation.Keep;
import kk.d;
import kotlin.Metadata;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000*\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0002\n\u0002\u0010\u0006\n\u0002\b\f\n\u0002\u0010\u000b\n\u0002\b\u000b\n\u0002\u0010\b\n\u0002\b\u0002\b\u0087\b\u0018\u00002\u00020\u0001B/\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\u0006\u0010\u0004\u001a\u00020\u0003\u0012\u0006\u0010\u0005\u001a\u00020\u0006\u0012\u0006\u0010\u0007\u001a\u00020\u0006\u0012\u0006\u0010\b\u001a\u00020\u0006¢\u0006\u0004\b\t\u0010\nJ\t\u0010\u0016\u001a\u00020\u0003HÆ\u0003J\t\u0010\u0017\u001a\u00020\u0003HÆ\u0003J\t\u0010\u0018\u001a\u00020\u0006HÆ\u0003J\t\u0010\u0019\u001a\u00020\u0006HÆ\u0003J\t\u0010\u001a\u001a\u00020\u0006HÆ\u0003J;\u0010\u001b\u001a\u00020\u00002\b\b\u0002\u0010\u0002\u001a\u00020\u00032\b\b\u0002\u0010\u0004\u001a\u00020\u00032\b\b\u0002\u0010\u0005\u001a\u00020\u00062\b\b\u0002\u0010\u0007\u001a\u00020\u00062\b\b\u0002\u0010\b\u001a\u00020\u0006HÆ\u0001J\u0013\u0010\u001c\u001a\u00020\u00132\b\u0010\u001d\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u001e\u001a\u00020\u001fHÖ\u0001J\t\u0010 \u001a\u00020\u0003HÖ\u0001R\u0011\u0010\u0002\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u000b\u0010\fR\u0011\u0010\u0004\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\r\u0010\fR\u0011\u0010\u0005\u001a\u00020\u0006¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\u000fR\u0011\u0010\u0007\u001a\u00020\u0006¢\u0006\b\n\u0000\u001a\u0004\b\u0010\u0010\u000fR\u0011\u0010\b\u001a\u00020\u0006¢\u0006\b\n\u0000\u001a\u0004\b\u0011\u0010\u000fR\u0011\u0010\u0012\u001a\u00020\u00138F¢\u0006\u0006\u001a\u0004\b\u0012\u0010\u0014R\u0011\u0010\u0015\u001a\u00020\u00138F¢\u0006\u0006\u001a\u0004\b\u0015\u0010\u0014¨\u0006!"}, d2 = {"Lsp/aicoin_kline/chart/data/EstimatedLiqVpcRecord;", "", "leverage", "", "direction", "fromPrice", "", "toPrice", "turnover", "<init>", "(Ljava/lang/String;Ljava/lang/String;DDD)V", "getLeverage", "()Ljava/lang/String;", "getDirection", "getFromPrice", "()D", "getToPrice", "getTurnover", "isLong", "", "()Z", "isShort", "component1", "component2", "component3", "component4", "component5", "copy", "equals", "other", "hashCode", "", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class EstimatedLiqVpcRecord {
    private final String direction;
    private final double fromPrice;
    private final String leverage;
    private final double toPrice;
    private final double turnover;

    public EstimatedLiqVpcRecord(String str, String str2, double d10, double d11, double d12) {
        this.leverage = str;
        this.direction = str2;
        this.fromPrice = d10;
        this.toPrice = d11;
        this.turnover = d12;
    }

    public static /* synthetic */ EstimatedLiqVpcRecord copy$default(EstimatedLiqVpcRecord estimatedLiqVpcRecord, String str, String str2, double d10, double d11, double d12, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            str = estimatedLiqVpcRecord.leverage;
        }
        if ((i10 & 2) != 0) {
            str2 = estimatedLiqVpcRecord.direction;
        }
        if ((i10 & 4) != 0) {
            d10 = estimatedLiqVpcRecord.fromPrice;
        }
        if ((i10 & 8) != 0) {
            d11 = estimatedLiqVpcRecord.toPrice;
        }
        if ((i10 & 16) != 0) {
            d12 = estimatedLiqVpcRecord.turnover;
        }
        double d13 = d12;
        double d14 = d11;
        return estimatedLiqVpcRecord.copy(str, str2, d10, d14, d13);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final String getLeverage() {
        return this.leverage;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final String getDirection() {
        return this.direction;
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    public final double getFromPrice() {
        return this.fromPrice;
    }

    /* JADX INFO: renamed from: component4, reason: from getter */
    public final double getToPrice() {
        return this.toPrice;
    }

    /* JADX INFO: renamed from: component5, reason: from getter */
    public final double getTurnover() {
        return this.turnover;
    }

    public final EstimatedLiqVpcRecord copy(String leverage, String direction, double fromPrice, double toPrice, double turnover) {
        return new EstimatedLiqVpcRecord(leverage, direction, fromPrice, toPrice, turnover);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof EstimatedLiqVpcRecord)) {
            return false;
        }
        EstimatedLiqVpcRecord estimatedLiqVpcRecord = (EstimatedLiqVpcRecord) other;
        return AbstractC7609s.f(this.leverage, estimatedLiqVpcRecord.leverage) && AbstractC7609s.f(this.direction, estimatedLiqVpcRecord.direction) && Double.compare(this.fromPrice, estimatedLiqVpcRecord.fromPrice) == 0 && Double.compare(this.toPrice, estimatedLiqVpcRecord.toPrice) == 0 && Double.compare(this.turnover, estimatedLiqVpcRecord.turnover) == 0;
    }

    public final String getDirection() {
        return this.direction;
    }

    public final double getFromPrice() {
        return this.fromPrice;
    }

    public final String getLeverage() {
        return this.leverage;
    }

    public final double getToPrice() {
        return this.toPrice;
    }

    public final double getTurnover() {
        return this.turnover;
    }

    public int hashCode() {
        return Double.hashCode(this.turnover) + ((Double.hashCode(this.toPrice) + ((Double.hashCode(this.fromPrice) + d.a(this.direction, this.leverage.hashCode() * 31, 31)) * 31)) * 31);
    }

    public final boolean isLong() {
        return x.z(this.direction, "long", true);
    }

    public final boolean isShort() {
        return x.z(this.direction, "short", true);
    }

    public String toString() {
        return "EstimatedLiqVpcRecord(leverage=" + this.leverage + ", direction=" + this.direction + ", fromPrice=" + this.fromPrice + ", toPrice=" + this.toPrice + ", turnover=" + this.turnover + ')';
    }
}
