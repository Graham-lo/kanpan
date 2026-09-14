package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000(\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0002\b\n\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0002\b\u0087\b\u0018\u00002\u00020\u0001:\u0001\u0014B\u001b\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0005\u0010\u0006J\u000b\u0010\n\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u000b\u001a\u0004\u0018\u00010\u0003HÆ\u0003J!\u0010\f\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\r\u001a\u00020\u000e2\b\u0010\u000f\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0010\u001a\u00020\u0011HÖ\u0001J\t\u0010\u0012\u001a\u00020\u0013HÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0007\u0010\bR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\t\u0010\b¨\u0006\u0015"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/LiqHeatmapRemote;", "", "output", "Lsp/aicoin_kline/core/indicator/config/LiqHeatmapRemote$Output;", "app_output", "<init>", "(Lsp/aicoin_kline/core/indicator/config/LiqHeatmapRemote$Output;Lsp/aicoin_kline/core/indicator/config/LiqHeatmapRemote$Output;)V", "getOutput", "()Lsp/aicoin_kline/core/indicator/config/LiqHeatmapRemote$Output;", "getApp_output", "component1", "component2", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Output", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class LiqHeatmapRemote {
    private final Output app_output;
    private final Output output;

    @Keep
    @Metadata(d1 = {"\u0000\u001e\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000b\n\u0002\b\u000e\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0000\b\u0087\b\u0018\u00002\u00020\u0001B\u001f\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0005\u0010\u0006J\u0010\u0010\u000b\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\bJ\u0010\u0010\f\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\bJ&\u0010\r\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0003HÆ\u0001¢\u0006\u0002\u0010\u000eJ\u0013\u0010\u000f\u001a\u00020\u00032\b\u0010\u0010\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0011\u001a\u00020\u0012HÖ\u0001J\t\u0010\u0013\u001a\u00020\u0014HÖ\u0001R\u001a\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\t\u001a\u0004\b\u0007\u0010\bR\u001a\u0010\u0004\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\t\u001a\u0004\b\n\u0010\b¨\u0006\u0015"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/LiqHeatmapRemote$Output;", "", "heatmapShowMagnifier", "", "heatmapShowTurnover", "<init>", "(Ljava/lang/Boolean;Ljava/lang/Boolean;)V", "getHeatmapShowMagnifier", "()Ljava/lang/Boolean;", "Ljava/lang/Boolean;", "getHeatmapShowTurnover", "component1", "component2", "copy", "(Ljava/lang/Boolean;Ljava/lang/Boolean;)Lsp/aicoin_kline/core/indicator/config/LiqHeatmapRemote$Output;", "equals", "other", "hashCode", "", "toString", "", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Output {

        @SerializedName("heatmap_showMagnifier")
        private final Boolean heatmapShowMagnifier;

        @SerializedName("heatmap_showTurnover")
        private final Boolean heatmapShowTurnover;

        public Output() {
            this(null, null, 3, null);
        }

        public Output(Boolean bool, Boolean bool2) {
            this.heatmapShowMagnifier = bool;
            this.heatmapShowTurnover = bool2;
        }

        public /* synthetic */ Output(Boolean bool, Boolean bool2, int i10, DefaultConstructorMarker defaultConstructorMarker) {
            this((i10 & 1) != 0 ? null : bool, (i10 & 2) != 0 ? null : bool2);
        }

        public static /* synthetic */ Output copy$default(Output output, Boolean bool, Boolean bool2, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                bool = output.heatmapShowMagnifier;
            }
            if ((i10 & 2) != 0) {
                bool2 = output.heatmapShowTurnover;
            }
            return output.copy(bool, bool2);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Boolean getHeatmapShowMagnifier() {
            return this.heatmapShowMagnifier;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final Boolean getHeatmapShowTurnover() {
            return this.heatmapShowTurnover;
        }

        public final Output copy(Boolean heatmapShowMagnifier, Boolean heatmapShowTurnover) {
            return new Output(heatmapShowMagnifier, heatmapShowTurnover);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Output)) {
                return false;
            }
            Output output = (Output) other;
            return AbstractC7609s.f(this.heatmapShowMagnifier, output.heatmapShowMagnifier) && AbstractC7609s.f(this.heatmapShowTurnover, output.heatmapShowTurnover);
        }

        public final Boolean getHeatmapShowMagnifier() {
            return this.heatmapShowMagnifier;
        }

        public final Boolean getHeatmapShowTurnover() {
            return this.heatmapShowTurnover;
        }

        public int hashCode() {
            Boolean bool = this.heatmapShowMagnifier;
            int iHashCode = (bool == null ? 0 : bool.hashCode()) * 31;
            Boolean bool2 = this.heatmapShowTurnover;
            return iHashCode + (bool2 != null ? bool2.hashCode() : 0);
        }

        public String toString() {
            return "Output(heatmapShowMagnifier=" + this.heatmapShowMagnifier + ", heatmapShowTurnover=" + this.heatmapShowTurnover + ')';
        }
    }

    public LiqHeatmapRemote(Output output, Output output2) {
        this.output = output;
        this.app_output = output2;
    }

    public static /* synthetic */ LiqHeatmapRemote copy$default(LiqHeatmapRemote liqHeatmapRemote, Output output, Output output2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            output = liqHeatmapRemote.output;
        }
        if ((i10 & 2) != 0) {
            output2 = liqHeatmapRemote.app_output;
        }
        return liqHeatmapRemote.copy(output, output2);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final Output getOutput() {
        return this.output;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final Output getApp_output() {
        return this.app_output;
    }

    public final LiqHeatmapRemote copy(Output output, Output app_output) {
        return new LiqHeatmapRemote(output, app_output);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof LiqHeatmapRemote)) {
            return false;
        }
        LiqHeatmapRemote liqHeatmapRemote = (LiqHeatmapRemote) other;
        return AbstractC7609s.f(this.output, liqHeatmapRemote.output) && AbstractC7609s.f(this.app_output, liqHeatmapRemote.app_output);
    }

    public final Output getApp_output() {
        return this.app_output;
    }

    public final Output getOutput() {
        return this.output;
    }

    public int hashCode() {
        Output output = this.output;
        int iHashCode = (output == null ? 0 : output.hashCode()) * 31;
        Output output2 = this.app_output;
        return iHashCode + (output2 != null ? output2.hashCode() : 0);
    }

    public String toString() {
        return "LiqHeatmapRemote(output=" + this.output + ", app_output=" + this.app_output + ')';
    }
}
