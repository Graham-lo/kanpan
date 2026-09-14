package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000.\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0010\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0003\b\u0087\b\u0018\u00002\u00020\u0001:\u0002\u001c\u001dB/\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\b\u0010\tJ\u000b\u0010\u0010\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u0011\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0012\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0013\u001a\u0004\u0018\u00010\u0003HÆ\u0003J9\u0010\u0014\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\u0015\u001a\u00020\u00162\b\u0010\u0017\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0018\u001a\u00020\u0019HÖ\u0001J\t\u0010\u001a\u001a\u00020\u001bHÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\n\u0010\u000bR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\f\u0010\rR\u0013\u0010\u0006\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\rR\u0013\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u000f\u0010\u000b¨\u0006\u001e"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/VrRemote;", "", "input", "Lsp/aicoin_kline/core/indicator/config/VrRemote$Input;", "output", "Lsp/aicoin_kline/core/indicator/config/VrRemote$Output;", "app_output", "app_input", "<init>", "(Lsp/aicoin_kline/core/indicator/config/VrRemote$Input;Lsp/aicoin_kline/core/indicator/config/VrRemote$Output;Lsp/aicoin_kline/core/indicator/config/VrRemote$Output;Lsp/aicoin_kline/core/indicator/config/VrRemote$Input;)V", "getInput", "()Lsp/aicoin_kline/core/indicator/config/VrRemote$Input;", "getOutput", "()Lsp/aicoin_kline/core/indicator/config/VrRemote$Output;", "getApp_output", "getApp_input", "component1", "component2", "component3", "component4", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Input", "Output", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class VrRemote {
    private final Input app_input;
    private final Output app_output;
    private final Input input;
    private final Output output;

    @Keep
    @Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0002\b\f\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0010\u000e\n\u0000\b\u0087\b\u0018\u00002\u00020\u0001B\u001b\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0005\u0010\u0006J\u0010\u0010\u000b\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\bJ\u0010\u0010\f\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\bJ&\u0010\r\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0003HÆ\u0001¢\u0006\u0002\u0010\u000eJ\u0013\u0010\u000f\u001a\u00020\u00102\b\u0010\u0011\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0012\u001a\u00020\u0003HÖ\u0001J\t\u0010\u0013\u001a\u00020\u0014HÖ\u0001R\u0015\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\t\u001a\u0004\b\u0007\u0010\bR\u0015\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\t\u001a\u0004\b\n\u0010\b¨\u0006\u0015"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/VrRemote$Input;", "", "cc", "", "mac", "<init>", "(Ljava/lang/Integer;Ljava/lang/Integer;)V", "getCc", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getMac", "component1", "component2", "copy", "(Ljava/lang/Integer;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/VrRemote$Input;", "equals", "", "other", "hashCode", "toString", "", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Input {
        private final Integer cc;
        private final Integer mac;

        public Input(Integer num, Integer num2) {
            this.cc = num;
            this.mac = num2;
        }

        public static /* synthetic */ Input copy$default(Input input, Integer num, Integer num2, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                num = input.cc;
            }
            if ((i10 & 2) != 0) {
                num2 = input.mac;
            }
            return input.copy(num, num2);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Integer getCc() {
            return this.cc;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final Integer getMac() {
            return this.mac;
        }

        public final Input copy(Integer cc2, Integer mac) {
            return new Input(cc2, mac);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Input)) {
                return false;
            }
            Input input = (Input) other;
            return AbstractC7609s.f(this.cc, input.cc) && AbstractC7609s.f(this.mac, input.mac);
        }

        public final Integer getCc() {
            return this.cc;
        }

        public final Integer getMac() {
            return this.mac;
        }

        public int hashCode() {
            Integer num = this.cc;
            int iHashCode = (num == null ? 0 : num.hashCode()) * 31;
            Integer num2 = this.mac;
            return iHashCode + (num2 != null ? num2.hashCode() : 0);
        }

        public String toString() {
            StringBuilder sb2 = new StringBuilder("Input(cc=");
            sb2.append(this.cc);
            sb2.append(", mac=");
            return kk.b.a(sb2, this.mac, ')');
        }
    }

    @Keep
    @Metadata(d1 = {"\u0000\u001e\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\b\n\u0002\b\u001d\b\u0087\b\u0018\u00002\u00020\u0001BO\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u0007¢\u0006\u0004\b\u000b\u0010\fJ\u0010\u0010\u0018\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u000eJ\u000b\u0010\u0019\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010\u001a\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0013J\u0010\u0010\u001b\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u000eJ\u000b\u0010\u001c\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010\u001d\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0013JV\u0010\u001e\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u0007HÆ\u0001¢\u0006\u0002\u0010\u001fJ\u0013\u0010 \u001a\u00020\u00032\b\u0010!\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\"\u001a\u00020\u0007HÖ\u0001J\t\u0010#\u001a\u00020\u0005HÖ\u0001R\u001a\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u000f\u001a\u0004\b\r\u0010\u000eR\u0018\u0010\u0004\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0010\u0010\u0011R\u001a\u0010\u0006\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0014\u001a\u0004\b\u0012\u0010\u0013R\u001a\u0010\b\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u000f\u001a\u0004\b\u0015\u0010\u000eR\u0018\u0010\t\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0016\u0010\u0011R\u001a\u0010\n\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0014\u001a\u0004\b\u0017\u0010\u0013¨\u0006$"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/VrRemote$Output;", "", "maVrDisabled", "", "maVrLineColor", "", "maVrLineWidth", "", "vrDisabled", "vrLineColor", "vrLineWidth", "<init>", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)V", "getMaVrDisabled", "()Ljava/lang/Boolean;", "Ljava/lang/Boolean;", "getMaVrLineColor", "()Ljava/lang/String;", "getMaVrLineWidth", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getVrDisabled", "getVrLineColor", "getVrLineWidth", "component1", "component2", "component3", "component4", "component5", "component6", "copy", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/VrRemote$Output;", "equals", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Output {

        @SerializedName("maVr_disabled")
        private final Boolean maVrDisabled;

        @SerializedName("maVr_lineColor")
        private final String maVrLineColor;

        @SerializedName("maVr_lineWidth")
        private final Integer maVrLineWidth;

        @SerializedName("vr_disabled")
        private final Boolean vrDisabled;

        @SerializedName("vr_lineColor")
        private final String vrLineColor;

        @SerializedName("vr_lineWidth")
        private final Integer vrLineWidth;

        public Output() {
            this(null, null, null, null, null, null, 63, null);
        }

        public Output(Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2) {
            this.maVrDisabled = bool;
            this.maVrLineColor = str;
            this.maVrLineWidth = num;
            this.vrDisabled = bool2;
            this.vrLineColor = str2;
            this.vrLineWidth = num2;
        }

        public /* synthetic */ Output(Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2, int i10, DefaultConstructorMarker defaultConstructorMarker) {
            this((i10 & 1) != 0 ? null : bool, (i10 & 2) != 0 ? null : str, (i10 & 4) != 0 ? null : num, (i10 & 8) != 0 ? null : bool2, (i10 & 16) != 0 ? null : str2, (i10 & 32) != 0 ? null : num2);
        }

        public static /* synthetic */ Output copy$default(Output output, Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                bool = output.maVrDisabled;
            }
            if ((i10 & 2) != 0) {
                str = output.maVrLineColor;
            }
            if ((i10 & 4) != 0) {
                num = output.maVrLineWidth;
            }
            if ((i10 & 8) != 0) {
                bool2 = output.vrDisabled;
            }
            if ((i10 & 16) != 0) {
                str2 = output.vrLineColor;
            }
            if ((i10 & 32) != 0) {
                num2 = output.vrLineWidth;
            }
            String str3 = str2;
            Integer num3 = num2;
            return output.copy(bool, str, num, bool2, str3, num3);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Boolean getMaVrDisabled() {
            return this.maVrDisabled;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final String getMaVrLineColor() {
            return this.maVrLineColor;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final Integer getMaVrLineWidth() {
            return this.maVrLineWidth;
        }

        /* JADX INFO: renamed from: component4, reason: from getter */
        public final Boolean getVrDisabled() {
            return this.vrDisabled;
        }

        /* JADX INFO: renamed from: component5, reason: from getter */
        public final String getVrLineColor() {
            return this.vrLineColor;
        }

        /* JADX INFO: renamed from: component6, reason: from getter */
        public final Integer getVrLineWidth() {
            return this.vrLineWidth;
        }

        public final Output copy(Boolean maVrDisabled, String maVrLineColor, Integer maVrLineWidth, Boolean vrDisabled, String vrLineColor, Integer vrLineWidth) {
            return new Output(maVrDisabled, maVrLineColor, maVrLineWidth, vrDisabled, vrLineColor, vrLineWidth);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Output)) {
                return false;
            }
            Output output = (Output) other;
            return AbstractC7609s.f(this.maVrDisabled, output.maVrDisabled) && AbstractC7609s.f(this.maVrLineColor, output.maVrLineColor) && AbstractC7609s.f(this.maVrLineWidth, output.maVrLineWidth) && AbstractC7609s.f(this.vrDisabled, output.vrDisabled) && AbstractC7609s.f(this.vrLineColor, output.vrLineColor) && AbstractC7609s.f(this.vrLineWidth, output.vrLineWidth);
        }

        public final Boolean getMaVrDisabled() {
            return this.maVrDisabled;
        }

        public final String getMaVrLineColor() {
            return this.maVrLineColor;
        }

        public final Integer getMaVrLineWidth() {
            return this.maVrLineWidth;
        }

        public final Boolean getVrDisabled() {
            return this.vrDisabled;
        }

        public final String getVrLineColor() {
            return this.vrLineColor;
        }

        public final Integer getVrLineWidth() {
            return this.vrLineWidth;
        }

        public int hashCode() {
            Boolean bool = this.maVrDisabled;
            int iHashCode = (bool == null ? 0 : bool.hashCode()) * 31;
            String str = this.maVrLineColor;
            int iHashCode2 = (iHashCode + (str == null ? 0 : str.hashCode())) * 31;
            Integer num = this.maVrLineWidth;
            int iHashCode3 = (iHashCode2 + (num == null ? 0 : num.hashCode())) * 31;
            Boolean bool2 = this.vrDisabled;
            int iHashCode4 = (iHashCode3 + (bool2 == null ? 0 : bool2.hashCode())) * 31;
            String str2 = this.vrLineColor;
            int iHashCode5 = (iHashCode4 + (str2 == null ? 0 : str2.hashCode())) * 31;
            Integer num2 = this.vrLineWidth;
            return iHashCode5 + (num2 != null ? num2.hashCode() : 0);
        }

        public String toString() {
            StringBuilder sb2 = new StringBuilder("Output(maVrDisabled=");
            sb2.append(this.maVrDisabled);
            sb2.append(", maVrLineColor=");
            sb2.append(this.maVrLineColor);
            sb2.append(", maVrLineWidth=");
            sb2.append(this.maVrLineWidth);
            sb2.append(", vrDisabled=");
            sb2.append(this.vrDisabled);
            sb2.append(", vrLineColor=");
            sb2.append(this.vrLineColor);
            sb2.append(", vrLineWidth=");
            return kk.b.a(sb2, this.vrLineWidth, ')');
        }
    }

    public VrRemote(Input input, Output output, Output output2, Input input2) {
        this.input = input;
        this.output = output;
        this.app_output = output2;
        this.app_input = input2;
    }

    public static /* synthetic */ VrRemote copy$default(VrRemote vrRemote, Input input, Output output, Output output2, Input input2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            input = vrRemote.input;
        }
        if ((i10 & 2) != 0) {
            output = vrRemote.output;
        }
        if ((i10 & 4) != 0) {
            output2 = vrRemote.app_output;
        }
        if ((i10 & 8) != 0) {
            input2 = vrRemote.app_input;
        }
        return vrRemote.copy(input, output, output2, input2);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final Input getInput() {
        return this.input;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final Output getOutput() {
        return this.output;
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    public final Output getApp_output() {
        return this.app_output;
    }

    /* JADX INFO: renamed from: component4, reason: from getter */
    public final Input getApp_input() {
        return this.app_input;
    }

    public final VrRemote copy(Input input, Output output, Output app_output, Input app_input) {
        return new VrRemote(input, output, app_output, app_input);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof VrRemote)) {
            return false;
        }
        VrRemote vrRemote = (VrRemote) other;
        return AbstractC7609s.f(this.input, vrRemote.input) && AbstractC7609s.f(this.output, vrRemote.output) && AbstractC7609s.f(this.app_output, vrRemote.app_output) && AbstractC7609s.f(this.app_input, vrRemote.app_input);
    }

    public final Input getApp_input() {
        return this.app_input;
    }

    public final Output getApp_output() {
        return this.app_output;
    }

    public final Input getInput() {
        return this.input;
    }

    public final Output getOutput() {
        return this.output;
    }

    public int hashCode() {
        Input input = this.input;
        int iHashCode = (input == null ? 0 : input.hashCode()) * 31;
        Output output = this.output;
        int iHashCode2 = (iHashCode + (output == null ? 0 : output.hashCode())) * 31;
        Output output2 = this.app_output;
        int iHashCode3 = (iHashCode2 + (output2 == null ? 0 : output2.hashCode())) * 31;
        Input input2 = this.app_input;
        return iHashCode3 + (input2 != null ? input2.hashCode() : 0);
    }

    public String toString() {
        return "VrRemote(input=" + this.input + ", output=" + this.output + ", app_output=" + this.app_output + ", app_input=" + this.app_input + ')';
    }
}
