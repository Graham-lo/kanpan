package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000(\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0002\b\n\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0002\b\u0087\b\u0018\u00002\u00020\u0001:\u0001\u0014B\u001b\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0005\u0010\u0006J\u000b\u0010\n\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u000b\u001a\u0004\u0018\u00010\u0003HÆ\u0003J!\u0010\f\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\r\u001a\u00020\u000e2\b\u0010\u000f\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0010\u001a\u00020\u0011HÖ\u0001J\t\u0010\u0012\u001a\u00020\u0013HÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0007\u0010\bR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\t\u0010\b¨\u0006\u0015"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/PositionRemote;", "", "output", "Lsp/aicoin_kline/core/indicator/config/PositionRemote$Output;", "app_output", "<init>", "(Lsp/aicoin_kline/core/indicator/config/PositionRemote$Output;Lsp/aicoin_kline/core/indicator/config/PositionRemote$Output;)V", "getOutput", "()Lsp/aicoin_kline/core/indicator/config/PositionRemote$Output;", "getApp_output", "component1", "component2", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Output", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class PositionRemote {
    private final Output app_output;
    private final Output output;

    @Keep
    @Metadata(d1 = {"\u0000\u001e\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\b\n\u0002\b\u0014\b\u0087\b\u0018\u00002\u00020\u0001B+\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0007¢\u0006\u0004\b\b\u0010\tJ\u0010\u0010\u0012\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u000bJ\u000b\u0010\u0013\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010\u0014\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0010J2\u0010\u0015\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0007HÆ\u0001¢\u0006\u0002\u0010\u0016J\u0013\u0010\u0017\u001a\u00020\u00032\b\u0010\u0018\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0019\u001a\u00020\u0007HÖ\u0001J\t\u0010\u001a\u001a\u00020\u0005HÖ\u0001R\u001a\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\f\u001a\u0004\b\n\u0010\u000bR\u0018\u0010\u0004\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\r\u0010\u000eR\u001a\u0010\u0006\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0011\u001a\u0004\b\u000f\u0010\u0010¨\u0006\u001b"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/PositionRemote$Output;", "", "positionDisabled", "", "positionLineColor", "", "positionLineWidth", "", "<init>", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)V", "getPositionDisabled", "()Ljava/lang/Boolean;", "Ljava/lang/Boolean;", "getPositionLineColor", "()Ljava/lang/String;", "getPositionLineWidth", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "component1", "component2", "component3", "copy", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/PositionRemote$Output;", "equals", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Output {

        @SerializedName("position_disabled")
        private final Boolean positionDisabled;

        @SerializedName("position_lineColor")
        private final String positionLineColor;

        @SerializedName("position_lineWidth")
        private final Integer positionLineWidth;

        public Output() {
            this(null, null, null, 7, null);
        }

        public Output(Boolean bool, String str, Integer num) {
            this.positionDisabled = bool;
            this.positionLineColor = str;
            this.positionLineWidth = num;
        }

        public /* synthetic */ Output(Boolean bool, String str, Integer num, int i10, DefaultConstructorMarker defaultConstructorMarker) {
            this((i10 & 1) != 0 ? null : bool, (i10 & 2) != 0 ? null : str, (i10 & 4) != 0 ? null : num);
        }

        public static /* synthetic */ Output copy$default(Output output, Boolean bool, String str, Integer num, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                bool = output.positionDisabled;
            }
            if ((i10 & 2) != 0) {
                str = output.positionLineColor;
            }
            if ((i10 & 4) != 0) {
                num = output.positionLineWidth;
            }
            return output.copy(bool, str, num);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Boolean getPositionDisabled() {
            return this.positionDisabled;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final String getPositionLineColor() {
            return this.positionLineColor;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final Integer getPositionLineWidth() {
            return this.positionLineWidth;
        }

        public final Output copy(Boolean positionDisabled, String positionLineColor, Integer positionLineWidth) {
            return new Output(positionDisabled, positionLineColor, positionLineWidth);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Output)) {
                return false;
            }
            Output output = (Output) other;
            return AbstractC7609s.f(this.positionDisabled, output.positionDisabled) && AbstractC7609s.f(this.positionLineColor, output.positionLineColor) && AbstractC7609s.f(this.positionLineWidth, output.positionLineWidth);
        }

        public final Boolean getPositionDisabled() {
            return this.positionDisabled;
        }

        public final String getPositionLineColor() {
            return this.positionLineColor;
        }

        public final Integer getPositionLineWidth() {
            return this.positionLineWidth;
        }

        public int hashCode() {
            Boolean bool = this.positionDisabled;
            int iHashCode = (bool == null ? 0 : bool.hashCode()) * 31;
            String str = this.positionLineColor;
            int iHashCode2 = (iHashCode + (str == null ? 0 : str.hashCode())) * 31;
            Integer num = this.positionLineWidth;
            return iHashCode2 + (num != null ? num.hashCode() : 0);
        }

        public String toString() {
            StringBuilder sb2 = new StringBuilder("Output(positionDisabled=");
            sb2.append(this.positionDisabled);
            sb2.append(", positionLineColor=");
            sb2.append(this.positionLineColor);
            sb2.append(", positionLineWidth=");
            return kk.b.a(sb2, this.positionLineWidth, ')');
        }
    }

    public PositionRemote(Output output, Output output2) {
        this.output = output;
        this.app_output = output2;
    }

    public static /* synthetic */ PositionRemote copy$default(PositionRemote positionRemote, Output output, Output output2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            output = positionRemote.output;
        }
        if ((i10 & 2) != 0) {
            output2 = positionRemote.app_output;
        }
        return positionRemote.copy(output, output2);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final Output getOutput() {
        return this.output;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final Output getApp_output() {
        return this.app_output;
    }

    public final PositionRemote copy(Output output, Output app_output) {
        return new PositionRemote(output, app_output);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof PositionRemote)) {
            return false;
        }
        PositionRemote positionRemote = (PositionRemote) other;
        return AbstractC7609s.f(this.output, positionRemote.output) && AbstractC7609s.f(this.app_output, positionRemote.app_output);
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
        return "PositionRemote(output=" + this.output + ", app_output=" + this.app_output + ')';
    }
}
