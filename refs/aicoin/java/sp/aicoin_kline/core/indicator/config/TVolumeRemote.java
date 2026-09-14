package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000(\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0002\b\n\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0002\b\u0087\b\u0018\u00002\u00020\u0001:\u0001\u0014B\u001b\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0005\u0010\u0006J\u000b\u0010\n\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u000b\u001a\u0004\u0018\u00010\u0003HÆ\u0003J!\u0010\f\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\r\u001a\u00020\u000e2\b\u0010\u000f\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0010\u001a\u00020\u0011HÖ\u0001J\t\u0010\u0012\u001a\u00020\u0013HÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0007\u0010\bR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\t\u0010\b¨\u0006\u0015"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/TVolumeRemote;", "", "output", "Lsp/aicoin_kline/core/indicator/config/TVolumeRemote$Output;", "app_output", "<init>", "(Lsp/aicoin_kline/core/indicator/config/TVolumeRemote$Output;Lsp/aicoin_kline/core/indicator/config/TVolumeRemote$Output;)V", "getOutput", "()Lsp/aicoin_kline/core/indicator/config/TVolumeRemote$Output;", "getApp_output", "component1", "component2", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Output", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class TVolumeRemote {
    private final Output app_output;
    private final Output output;

    @Keep
    @Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\u000b\n\u0002\b\u0011\n\u0002\u0010\b\n\u0002\b\u0002\b\u0087\b\u0018\u00002\u00020\u0001B)\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0005¢\u0006\u0004\b\u0007\u0010\bJ\u000b\u0010\u000f\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0010\u0010\u0010\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\fJ\u0010\u0010\u0011\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\fJ2\u0010\u0012\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0005HÆ\u0001¢\u0006\u0002\u0010\u0013J\u0013\u0010\u0014\u001a\u00020\u00052\b\u0010\u0015\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0016\u001a\u00020\u0017HÖ\u0001J\t\u0010\u0018\u001a\u00020\u0003HÖ\u0001R\u0018\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\t\u0010\nR\u001a\u0010\u0004\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\r\u001a\u0004\b\u000b\u0010\fR\u001a\u0010\u0006\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\r\u001a\u0004\b\u000e\u0010\f¨\u0006\u0019"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/TVolumeRemote$Output;", "", "tVolumeColor", "", "tVolumeDisabled", "", "tVolumeFill", "<init>", "(Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/Boolean;)V", "getTVolumeColor", "()Ljava/lang/String;", "getTVolumeDisabled", "()Ljava/lang/Boolean;", "Ljava/lang/Boolean;", "getTVolumeFill", "component1", "component2", "component3", "copy", "(Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/Boolean;)Lsp/aicoin_kline/core/indicator/config/TVolumeRemote$Output;", "equals", "other", "hashCode", "", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Output {

        @SerializedName("tVolume_color")
        private final String tVolumeColor;

        @SerializedName("tVolume_disabled")
        private final Boolean tVolumeDisabled;

        @SerializedName("tVolume_fill")
        private final Boolean tVolumeFill;

        public Output(String str, Boolean bool, Boolean bool2) {
            this.tVolumeColor = str;
            this.tVolumeDisabled = bool;
            this.tVolumeFill = bool2;
        }

        public /* synthetic */ Output(String str, Boolean bool, Boolean bool2, int i10, DefaultConstructorMarker defaultConstructorMarker) {
            this((i10 & 1) != 0 ? null : str, bool, (i10 & 4) != 0 ? null : bool2);
        }

        public static /* synthetic */ Output copy$default(Output output, String str, Boolean bool, Boolean bool2, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                str = output.tVolumeColor;
            }
            if ((i10 & 2) != 0) {
                bool = output.tVolumeDisabled;
            }
            if ((i10 & 4) != 0) {
                bool2 = output.tVolumeFill;
            }
            return output.copy(str, bool, bool2);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final String getTVolumeColor() {
            return this.tVolumeColor;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final Boolean getTVolumeDisabled() {
            return this.tVolumeDisabled;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final Boolean getTVolumeFill() {
            return this.tVolumeFill;
        }

        public final Output copy(String tVolumeColor, Boolean tVolumeDisabled, Boolean tVolumeFill) {
            return new Output(tVolumeColor, tVolumeDisabled, tVolumeFill);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Output)) {
                return false;
            }
            Output output = (Output) other;
            return AbstractC7609s.f(this.tVolumeColor, output.tVolumeColor) && AbstractC7609s.f(this.tVolumeDisabled, output.tVolumeDisabled) && AbstractC7609s.f(this.tVolumeFill, output.tVolumeFill);
        }

        public final String getTVolumeColor() {
            return this.tVolumeColor;
        }

        public final Boolean getTVolumeDisabled() {
            return this.tVolumeDisabled;
        }

        public final Boolean getTVolumeFill() {
            return this.tVolumeFill;
        }

        public int hashCode() {
            String str = this.tVolumeColor;
            int iHashCode = (str == null ? 0 : str.hashCode()) * 31;
            Boolean bool = this.tVolumeDisabled;
            int iHashCode2 = (iHashCode + (bool == null ? 0 : bool.hashCode())) * 31;
            Boolean bool2 = this.tVolumeFill;
            return iHashCode2 + (bool2 != null ? bool2.hashCode() : 0);
        }

        public String toString() {
            return "Output(tVolumeColor=" + this.tVolumeColor + ", tVolumeDisabled=" + this.tVolumeDisabled + ", tVolumeFill=" + this.tVolumeFill + ')';
        }
    }

    public TVolumeRemote(Output output, Output output2) {
        this.output = output;
        this.app_output = output2;
    }

    public static /* synthetic */ TVolumeRemote copy$default(TVolumeRemote tVolumeRemote, Output output, Output output2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            output = tVolumeRemote.output;
        }
        if ((i10 & 2) != 0) {
            output2 = tVolumeRemote.app_output;
        }
        return tVolumeRemote.copy(output, output2);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final Output getOutput() {
        return this.output;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final Output getApp_output() {
        return this.app_output;
    }

    public final TVolumeRemote copy(Output output, Output app_output) {
        return new TVolumeRemote(output, app_output);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof TVolumeRemote)) {
            return false;
        }
        TVolumeRemote tVolumeRemote = (TVolumeRemote) other;
        return AbstractC7609s.f(this.output, tVolumeRemote.output) && AbstractC7609s.f(this.app_output, tVolumeRemote.app_output);
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
        return "TVolumeRemote(output=" + this.output + ", app_output=" + this.app_output + ')';
    }
}
