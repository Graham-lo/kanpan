package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000(\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0002\b\n\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0002\b\u0087\b\u0018\u00002\u00020\u0001:\u0001\u0014B\u001b\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0005\u0010\u0006J\u000b\u0010\n\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u000b\u001a\u0004\u0018\u00010\u0003HÆ\u0003J!\u0010\f\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\r\u001a\u00020\u000e2\b\u0010\u000f\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0010\u001a\u00020\u0011HÖ\u0001J\t\u0010\u0012\u001a\u00020\u0013HÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0007\u0010\bR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\t\u0010\b¨\u0006\u0015"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/AORemote;", "", "output", "Lsp/aicoin_kline/core/indicator/config/AORemote$Output;", "app_output", "<init>", "(Lsp/aicoin_kline/core/indicator/config/AORemote$Output;Lsp/aicoin_kline/core/indicator/config/AORemote$Output;)V", "getOutput", "()Lsp/aicoin_kline/core/indicator/config/AORemote$Output;", "getApp_output", "component1", "component2", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Output", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class AORemote {
    private final Output app_output;
    private final Output output;

    @Keep
    @Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0017\n\u0002\u0010\b\n\u0002\b\u0002\b\u0087\b\u0018\u00002\u00020\u0001BC\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\t\u0010\nJ\u0010\u0010\u0013\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\fJ\u000b\u0010\u0014\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010\u0015\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\fJ\u000b\u0010\u0016\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010\u0017\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\fJJ\u0010\u0018\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u0003HÆ\u0001¢\u0006\u0002\u0010\u0019J\u0013\u0010\u001a\u001a\u00020\u00032\b\u0010\u001b\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u001c\u001a\u00020\u001dHÖ\u0001J\t\u0010\u001e\u001a\u00020\u0005HÖ\u0001R\u001a\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\r\u001a\u0004\b\u000b\u0010\fR\u0018\u0010\u0004\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\u000fR\u001a\u0010\u0006\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\r\u001a\u0004\b\u0010\u0010\fR\u0018\u0010\u0007\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0011\u0010\u000fR\u001a\u0010\b\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\r\u001a\u0004\b\u0012\u0010\f¨\u0006\u001f"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/AORemote$Output;", "", "aoDisabled", "", "aoFallColor", "", "aoFallFill", "aoRiseColor", "aoRiseFill", "<init>", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Boolean;)V", "getAoDisabled", "()Ljava/lang/Boolean;", "Ljava/lang/Boolean;", "getAoFallColor", "()Ljava/lang/String;", "getAoFallFill", "getAoRiseColor", "getAoRiseFill", "component1", "component2", "component3", "component4", "component5", "copy", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Boolean;)Lsp/aicoin_kline/core/indicator/config/AORemote$Output;", "equals", "other", "hashCode", "", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Output {

        @SerializedName("ao_disabled")
        private final Boolean aoDisabled;

        @SerializedName("ao_fall_color")
        private final String aoFallColor;

        @SerializedName("ao_fall_fill")
        private final Boolean aoFallFill;

        @SerializedName("ao_rise_color")
        private final String aoRiseColor;

        @SerializedName("ao_rise_fill")
        private final Boolean aoRiseFill;

        public Output() {
            this(null, null, null, null, null, 31, null);
        }

        public Output(Boolean bool, String str, Boolean bool2, String str2, Boolean bool3) {
            this.aoDisabled = bool;
            this.aoFallColor = str;
            this.aoFallFill = bool2;
            this.aoRiseColor = str2;
            this.aoRiseFill = bool3;
        }

        public /* synthetic */ Output(Boolean bool, String str, Boolean bool2, String str2, Boolean bool3, int i10, DefaultConstructorMarker defaultConstructorMarker) {
            this((i10 & 1) != 0 ? null : bool, (i10 & 2) != 0 ? null : str, (i10 & 4) != 0 ? null : bool2, (i10 & 8) != 0 ? null : str2, (i10 & 16) != 0 ? null : bool3);
        }

        public static /* synthetic */ Output copy$default(Output output, Boolean bool, String str, Boolean bool2, String str2, Boolean bool3, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                bool = output.aoDisabled;
            }
            if ((i10 & 2) != 0) {
                str = output.aoFallColor;
            }
            if ((i10 & 4) != 0) {
                bool2 = output.aoFallFill;
            }
            if ((i10 & 8) != 0) {
                str2 = output.aoRiseColor;
            }
            if ((i10 & 16) != 0) {
                bool3 = output.aoRiseFill;
            }
            Boolean bool4 = bool3;
            Boolean bool5 = bool2;
            return output.copy(bool, str, bool5, str2, bool4);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Boolean getAoDisabled() {
            return this.aoDisabled;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final String getAoFallColor() {
            return this.aoFallColor;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final Boolean getAoFallFill() {
            return this.aoFallFill;
        }

        /* JADX INFO: renamed from: component4, reason: from getter */
        public final String getAoRiseColor() {
            return this.aoRiseColor;
        }

        /* JADX INFO: renamed from: component5, reason: from getter */
        public final Boolean getAoRiseFill() {
            return this.aoRiseFill;
        }

        public final Output copy(Boolean aoDisabled, String aoFallColor, Boolean aoFallFill, String aoRiseColor, Boolean aoRiseFill) {
            return new Output(aoDisabled, aoFallColor, aoFallFill, aoRiseColor, aoRiseFill);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Output)) {
                return false;
            }
            Output output = (Output) other;
            return AbstractC7609s.f(this.aoDisabled, output.aoDisabled) && AbstractC7609s.f(this.aoFallColor, output.aoFallColor) && AbstractC7609s.f(this.aoFallFill, output.aoFallFill) && AbstractC7609s.f(this.aoRiseColor, output.aoRiseColor) && AbstractC7609s.f(this.aoRiseFill, output.aoRiseFill);
        }

        public final Boolean getAoDisabled() {
            return this.aoDisabled;
        }

        public final String getAoFallColor() {
            return this.aoFallColor;
        }

        public final Boolean getAoFallFill() {
            return this.aoFallFill;
        }

        public final String getAoRiseColor() {
            return this.aoRiseColor;
        }

        public final Boolean getAoRiseFill() {
            return this.aoRiseFill;
        }

        public int hashCode() {
            Boolean bool = this.aoDisabled;
            int iHashCode = (bool == null ? 0 : bool.hashCode()) * 31;
            String str = this.aoFallColor;
            int iHashCode2 = (iHashCode + (str == null ? 0 : str.hashCode())) * 31;
            Boolean bool2 = this.aoFallFill;
            int iHashCode3 = (iHashCode2 + (bool2 == null ? 0 : bool2.hashCode())) * 31;
            String str2 = this.aoRiseColor;
            int iHashCode4 = (iHashCode3 + (str2 == null ? 0 : str2.hashCode())) * 31;
            Boolean bool3 = this.aoRiseFill;
            return iHashCode4 + (bool3 != null ? bool3.hashCode() : 0);
        }

        public String toString() {
            return "Output(aoDisabled=" + this.aoDisabled + ", aoFallColor=" + this.aoFallColor + ", aoFallFill=" + this.aoFallFill + ", aoRiseColor=" + this.aoRiseColor + ", aoRiseFill=" + this.aoRiseFill + ')';
        }
    }

    public AORemote(Output output, Output output2) {
        this.output = output;
        this.app_output = output2;
    }

    public static /* synthetic */ AORemote copy$default(AORemote aORemote, Output output, Output output2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            output = aORemote.output;
        }
        if ((i10 & 2) != 0) {
            output2 = aORemote.app_output;
        }
        return aORemote.copy(output, output2);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final Output getOutput() {
        return this.output;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final Output getApp_output() {
        return this.app_output;
    }

    public final AORemote copy(Output output, Output app_output) {
        return new AORemote(output, app_output);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof AORemote)) {
            return false;
        }
        AORemote aORemote = (AORemote) other;
        return AbstractC7609s.f(this.output, aORemote.output) && AbstractC7609s.f(this.app_output, aORemote.app_output);
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
        return "AORemote(output=" + this.output + ", app_output=" + this.app_output + ')';
    }
}
