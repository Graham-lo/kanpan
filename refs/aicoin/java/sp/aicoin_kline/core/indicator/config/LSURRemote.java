package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000(\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0002\b\n\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0002\b\u0087\b\u0018\u00002\u00020\u0001:\u0001\u0014B\u001b\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0005\u0010\u0006J\u000b\u0010\n\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u000b\u001a\u0004\u0018\u00010\u0003HÆ\u0003J!\u0010\f\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\r\u001a\u00020\u000e2\b\u0010\u000f\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0010\u001a\u00020\u0011HÖ\u0001J\t\u0010\u0012\u001a\u00020\u0013HÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0007\u0010\bR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\t\u0010\b¨\u0006\u0015"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/LSURRemote;", "", "output", "Lsp/aicoin_kline/core/indicator/config/LSURRemote$Output;", "app_output", "<init>", "(Lsp/aicoin_kline/core/indicator/config/LSURRemote$Output;Lsp/aicoin_kline/core/indicator/config/LSURRemote$Output;)V", "getOutput", "()Lsp/aicoin_kline/core/indicator/config/LSURRemote$Output;", "getApp_output", "component1", "component2", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Output", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class LSURRemote {
    private final Output app_output;
    private final Output output;

    @Keep
    @Metadata(d1 = {"\u0000\u001e\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\b\n\u0002\b\u0014\b\u0087\b\u0018\u00002\u00020\u0001B+\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0007¢\u0006\u0004\b\b\u0010\tJ\u0010\u0010\u0012\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u000bJ\u000b\u0010\u0013\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010\u0014\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0010J2\u0010\u0015\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0007HÆ\u0001¢\u0006\u0002\u0010\u0016J\u0013\u0010\u0017\u001a\u00020\u00032\b\u0010\u0018\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0019\u001a\u00020\u0007HÖ\u0001J\t\u0010\u001a\u001a\u00020\u0005HÖ\u0001R\u001a\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\f\u001a\u0004\b\n\u0010\u000bR\u0018\u0010\u0004\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\r\u0010\u000eR\u001a\u0010\u0006\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0011\u001a\u0004\b\u000f\u0010\u0010¨\u0006\u001b"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/LSURRemote$Output;", "", "lsurDisabled", "", "lsurLineColor", "", "lsurLineWidth", "", "<init>", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)V", "getLsurDisabled", "()Ljava/lang/Boolean;", "Ljava/lang/Boolean;", "getLsurLineColor", "()Ljava/lang/String;", "getLsurLineWidth", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "component1", "component2", "component3", "copy", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/LSURRemote$Output;", "equals", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Output {

        @SerializedName("lsur_disabled")
        private final Boolean lsurDisabled;

        @SerializedName("lsur_lineColor")
        private final String lsurLineColor;

        @SerializedName("lsur_lineWidth")
        private final Integer lsurLineWidth;

        public Output() {
            this(null, null, null, 7, null);
        }

        public Output(Boolean bool, String str, Integer num) {
            this.lsurDisabled = bool;
            this.lsurLineColor = str;
            this.lsurLineWidth = num;
        }

        public /* synthetic */ Output(Boolean bool, String str, Integer num, int i10, DefaultConstructorMarker defaultConstructorMarker) {
            this((i10 & 1) != 0 ? null : bool, (i10 & 2) != 0 ? null : str, (i10 & 4) != 0 ? null : num);
        }

        public static /* synthetic */ Output copy$default(Output output, Boolean bool, String str, Integer num, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                bool = output.lsurDisabled;
            }
            if ((i10 & 2) != 0) {
                str = output.lsurLineColor;
            }
            if ((i10 & 4) != 0) {
                num = output.lsurLineWidth;
            }
            return output.copy(bool, str, num);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Boolean getLsurDisabled() {
            return this.lsurDisabled;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final String getLsurLineColor() {
            return this.lsurLineColor;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final Integer getLsurLineWidth() {
            return this.lsurLineWidth;
        }

        public final Output copy(Boolean lsurDisabled, String lsurLineColor, Integer lsurLineWidth) {
            return new Output(lsurDisabled, lsurLineColor, lsurLineWidth);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Output)) {
                return false;
            }
            Output output = (Output) other;
            return AbstractC7609s.f(this.lsurDisabled, output.lsurDisabled) && AbstractC7609s.f(this.lsurLineColor, output.lsurLineColor) && AbstractC7609s.f(this.lsurLineWidth, output.lsurLineWidth);
        }

        public final Boolean getLsurDisabled() {
            return this.lsurDisabled;
        }

        public final String getLsurLineColor() {
            return this.lsurLineColor;
        }

        public final Integer getLsurLineWidth() {
            return this.lsurLineWidth;
        }

        public int hashCode() {
            Boolean bool = this.lsurDisabled;
            int iHashCode = (bool == null ? 0 : bool.hashCode()) * 31;
            String str = this.lsurLineColor;
            int iHashCode2 = (iHashCode + (str == null ? 0 : str.hashCode())) * 31;
            Integer num = this.lsurLineWidth;
            return iHashCode2 + (num != null ? num.hashCode() : 0);
        }

        public String toString() {
            StringBuilder sb2 = new StringBuilder("Output(lsurDisabled=");
            sb2.append(this.lsurDisabled);
            sb2.append(", lsurLineColor=");
            sb2.append(this.lsurLineColor);
            sb2.append(", lsurLineWidth=");
            return kk.b.a(sb2, this.lsurLineWidth, ')');
        }
    }

    public LSURRemote(Output output, Output output2) {
        this.output = output;
        this.app_output = output2;
    }

    public static /* synthetic */ LSURRemote copy$default(LSURRemote lSURRemote, Output output, Output output2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            output = lSURRemote.output;
        }
        if ((i10 & 2) != 0) {
            output2 = lSURRemote.app_output;
        }
        return lSURRemote.copy(output, output2);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final Output getOutput() {
        return this.output;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final Output getApp_output() {
        return this.app_output;
    }

    public final LSURRemote copy(Output output, Output app_output) {
        return new LSURRemote(output, app_output);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof LSURRemote)) {
            return false;
        }
        LSURRemote lSURRemote = (LSURRemote) other;
        return AbstractC7609s.f(this.output, lSURRemote.output) && AbstractC7609s.f(this.app_output, lSURRemote.app_output);
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
        return "LSURRemote(output=" + this.output + ", app_output=" + this.app_output + ')';
    }
}
