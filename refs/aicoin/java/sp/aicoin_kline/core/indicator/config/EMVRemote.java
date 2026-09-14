package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000.\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0010\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0003\b\u0087\b\u0018\u00002\u00020\u0001:\u0002\u001c\u001dB/\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\b\u0010\tJ\u000b\u0010\u0010\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u0011\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0012\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0013\u001a\u0004\u0018\u00010\u0003HÆ\u0003J9\u0010\u0014\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\u0015\u001a\u00020\u00162\b\u0010\u0017\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0018\u001a\u00020\u0019HÖ\u0001J\t\u0010\u001a\u001a\u00020\u001bHÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\n\u0010\u000bR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\f\u0010\rR\u0013\u0010\u0006\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\rR\u0013\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u000f\u0010\u000b¨\u0006\u001e"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/EMVRemote;", "", "input", "Lsp/aicoin_kline/core/indicator/config/EMVRemote$Input;", "output", "Lsp/aicoin_kline/core/indicator/config/EMVRemote$Output;", "app_output", "app_input", "<init>", "(Lsp/aicoin_kline/core/indicator/config/EMVRemote$Input;Lsp/aicoin_kline/core/indicator/config/EMVRemote$Output;Lsp/aicoin_kline/core/indicator/config/EMVRemote$Output;Lsp/aicoin_kline/core/indicator/config/EMVRemote$Input;)V", "getInput", "()Lsp/aicoin_kline/core/indicator/config/EMVRemote$Input;", "getOutput", "()Lsp/aicoin_kline/core/indicator/config/EMVRemote$Output;", "getApp_output", "getApp_input", "component1", "component2", "component3", "component4", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Input", "Output", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class EMVRemote {
    private final Input app_input;
    private final Output app_output;
    private final Input input;
    private final Output output;

    @Keep
    @Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0002\b\f\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0010\u000e\n\u0000\b\u0087\b\u0018\u00002\u00020\u0001B\u001b\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0005\u0010\u0006J\u0010\u0010\u000b\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\bJ\u0010\u0010\f\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\bJ&\u0010\r\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0003HÆ\u0001¢\u0006\u0002\u0010\u000eJ\u0013\u0010\u000f\u001a\u00020\u00102\b\u0010\u0011\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0012\u001a\u00020\u0003HÖ\u0001J\t\u0010\u0013\u001a\u00020\u0014HÖ\u0001R\u0015\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\t\u001a\u0004\b\u0007\u0010\bR\u0015\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\t\u001a\u0004\b\n\u0010\b¨\u0006\u0015"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/EMVRemote$Input;", "", "mac1", "", "mac2", "<init>", "(Ljava/lang/Integer;Ljava/lang/Integer;)V", "getMac1", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getMac2", "component1", "component2", "copy", "(Ljava/lang/Integer;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/EMVRemote$Input;", "equals", "", "other", "hashCode", "toString", "", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Input {
        private final Integer mac1;
        private final Integer mac2;

        public Input(Integer num, Integer num2) {
            this.mac1 = num;
            this.mac2 = num2;
        }

        public static /* synthetic */ Input copy$default(Input input, Integer num, Integer num2, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                num = input.mac1;
            }
            if ((i10 & 2) != 0) {
                num2 = input.mac2;
            }
            return input.copy(num, num2);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Integer getMac1() {
            return this.mac1;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final Integer getMac2() {
            return this.mac2;
        }

        public final Input copy(Integer mac1, Integer mac2) {
            return new Input(mac1, mac2);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Input)) {
                return false;
            }
            Input input = (Input) other;
            return AbstractC7609s.f(this.mac1, input.mac1) && AbstractC7609s.f(this.mac2, input.mac2);
        }

        public final Integer getMac1() {
            return this.mac1;
        }

        public final Integer getMac2() {
            return this.mac2;
        }

        public int hashCode() {
            Integer num = this.mac1;
            int iHashCode = (num == null ? 0 : num.hashCode()) * 31;
            Integer num2 = this.mac2;
            return iHashCode + (num2 != null ? num2.hashCode() : 0);
        }

        public String toString() {
            StringBuilder sb2 = new StringBuilder("Input(mac1=");
            sb2.append(this.mac1);
            sb2.append(", mac2=");
            return kk.b.a(sb2, this.mac2, ')');
        }
    }

    @Keep
    @Metadata(d1 = {"\u0000\u001e\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\b\n\u0002\b\u001d\b\u0087\b\u0018\u00002\u00020\u0001BO\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u0007¢\u0006\u0004\b\u000b\u0010\fJ\u0010\u0010\u0018\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u000eJ\u000b\u0010\u0019\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010\u001a\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0013J\u0010\u0010\u001b\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u000eJ\u000b\u0010\u001c\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010\u001d\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0013JV\u0010\u001e\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u0007HÆ\u0001¢\u0006\u0002\u0010\u001fJ\u0013\u0010 \u001a\u00020\u00032\b\u0010!\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\"\u001a\u00020\u0007HÖ\u0001J\t\u0010#\u001a\u00020\u0005HÖ\u0001R\u001a\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u000f\u001a\u0004\b\r\u0010\u000eR\u0018\u0010\u0004\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0010\u0010\u0011R\u001a\u0010\u0006\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0014\u001a\u0004\b\u0012\u0010\u0013R\u001a\u0010\b\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u000f\u001a\u0004\b\u0015\u0010\u000eR\u0018\u0010\t\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0016\u0010\u0011R\u001a\u0010\n\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0014\u001a\u0004\b\u0017\u0010\u0013¨\u0006$"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/EMVRemote$Output;", "", "emvDisabled", "", "emvLineColor", "", "emvLineWidth", "", "maEmvDisabled", "maEmvLineColor", "maEmvLineWidth", "<init>", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)V", "getEmvDisabled", "()Ljava/lang/Boolean;", "Ljava/lang/Boolean;", "getEmvLineColor", "()Ljava/lang/String;", "getEmvLineWidth", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getMaEmvDisabled", "getMaEmvLineColor", "getMaEmvLineWidth", "component1", "component2", "component3", "component4", "component5", "component6", "copy", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/EMVRemote$Output;", "equals", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Output {

        @SerializedName("emv_disabled")
        private final Boolean emvDisabled;

        @SerializedName("emv_lineColor")
        private final String emvLineColor;

        @SerializedName("emv_lineWidth")
        private final Integer emvLineWidth;

        @SerializedName("maEmv_disabled")
        private final Boolean maEmvDisabled;

        @SerializedName("maEmv_lineColor")
        private final String maEmvLineColor;

        @SerializedName("maEmv_lineWidth")
        private final Integer maEmvLineWidth;

        public Output() {
            this(null, null, null, null, null, null, 63, null);
        }

        public Output(Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2) {
            this.emvDisabled = bool;
            this.emvLineColor = str;
            this.emvLineWidth = num;
            this.maEmvDisabled = bool2;
            this.maEmvLineColor = str2;
            this.maEmvLineWidth = num2;
        }

        public /* synthetic */ Output(Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2, int i10, DefaultConstructorMarker defaultConstructorMarker) {
            this((i10 & 1) != 0 ? null : bool, (i10 & 2) != 0 ? null : str, (i10 & 4) != 0 ? null : num, (i10 & 8) != 0 ? null : bool2, (i10 & 16) != 0 ? null : str2, (i10 & 32) != 0 ? null : num2);
        }

        public static /* synthetic */ Output copy$default(Output output, Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                bool = output.emvDisabled;
            }
            if ((i10 & 2) != 0) {
                str = output.emvLineColor;
            }
            if ((i10 & 4) != 0) {
                num = output.emvLineWidth;
            }
            if ((i10 & 8) != 0) {
                bool2 = output.maEmvDisabled;
            }
            if ((i10 & 16) != 0) {
                str2 = output.maEmvLineColor;
            }
            if ((i10 & 32) != 0) {
                num2 = output.maEmvLineWidth;
            }
            String str3 = str2;
            Integer num3 = num2;
            return output.copy(bool, str, num, bool2, str3, num3);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Boolean getEmvDisabled() {
            return this.emvDisabled;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final String getEmvLineColor() {
            return this.emvLineColor;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final Integer getEmvLineWidth() {
            return this.emvLineWidth;
        }

        /* JADX INFO: renamed from: component4, reason: from getter */
        public final Boolean getMaEmvDisabled() {
            return this.maEmvDisabled;
        }

        /* JADX INFO: renamed from: component5, reason: from getter */
        public final String getMaEmvLineColor() {
            return this.maEmvLineColor;
        }

        /* JADX INFO: renamed from: component6, reason: from getter */
        public final Integer getMaEmvLineWidth() {
            return this.maEmvLineWidth;
        }

        public final Output copy(Boolean emvDisabled, String emvLineColor, Integer emvLineWidth, Boolean maEmvDisabled, String maEmvLineColor, Integer maEmvLineWidth) {
            return new Output(emvDisabled, emvLineColor, emvLineWidth, maEmvDisabled, maEmvLineColor, maEmvLineWidth);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Output)) {
                return false;
            }
            Output output = (Output) other;
            return AbstractC7609s.f(this.emvDisabled, output.emvDisabled) && AbstractC7609s.f(this.emvLineColor, output.emvLineColor) && AbstractC7609s.f(this.emvLineWidth, output.emvLineWidth) && AbstractC7609s.f(this.maEmvDisabled, output.maEmvDisabled) && AbstractC7609s.f(this.maEmvLineColor, output.maEmvLineColor) && AbstractC7609s.f(this.maEmvLineWidth, output.maEmvLineWidth);
        }

        public final Boolean getEmvDisabled() {
            return this.emvDisabled;
        }

        public final String getEmvLineColor() {
            return this.emvLineColor;
        }

        public final Integer getEmvLineWidth() {
            return this.emvLineWidth;
        }

        public final Boolean getMaEmvDisabled() {
            return this.maEmvDisabled;
        }

        public final String getMaEmvLineColor() {
            return this.maEmvLineColor;
        }

        public final Integer getMaEmvLineWidth() {
            return this.maEmvLineWidth;
        }

        public int hashCode() {
            Boolean bool = this.emvDisabled;
            int iHashCode = (bool == null ? 0 : bool.hashCode()) * 31;
            String str = this.emvLineColor;
            int iHashCode2 = (iHashCode + (str == null ? 0 : str.hashCode())) * 31;
            Integer num = this.emvLineWidth;
            int iHashCode3 = (iHashCode2 + (num == null ? 0 : num.hashCode())) * 31;
            Boolean bool2 = this.maEmvDisabled;
            int iHashCode4 = (iHashCode3 + (bool2 == null ? 0 : bool2.hashCode())) * 31;
            String str2 = this.maEmvLineColor;
            int iHashCode5 = (iHashCode4 + (str2 == null ? 0 : str2.hashCode())) * 31;
            Integer num2 = this.maEmvLineWidth;
            return iHashCode5 + (num2 != null ? num2.hashCode() : 0);
        }

        public String toString() {
            StringBuilder sb2 = new StringBuilder("Output(emvDisabled=");
            sb2.append(this.emvDisabled);
            sb2.append(", emvLineColor=");
            sb2.append(this.emvLineColor);
            sb2.append(", emvLineWidth=");
            sb2.append(this.emvLineWidth);
            sb2.append(", maEmvDisabled=");
            sb2.append(this.maEmvDisabled);
            sb2.append(", maEmvLineColor=");
            sb2.append(this.maEmvLineColor);
            sb2.append(", maEmvLineWidth=");
            return kk.b.a(sb2, this.maEmvLineWidth, ')');
        }
    }

    public EMVRemote(Input input, Output output, Output output2, Input input2) {
        this.input = input;
        this.output = output;
        this.app_output = output2;
        this.app_input = input2;
    }

    public static /* synthetic */ EMVRemote copy$default(EMVRemote eMVRemote, Input input, Output output, Output output2, Input input2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            input = eMVRemote.input;
        }
        if ((i10 & 2) != 0) {
            output = eMVRemote.output;
        }
        if ((i10 & 4) != 0) {
            output2 = eMVRemote.app_output;
        }
        if ((i10 & 8) != 0) {
            input2 = eMVRemote.app_input;
        }
        return eMVRemote.copy(input, output, output2, input2);
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

    public final EMVRemote copy(Input input, Output output, Output app_output, Input app_input) {
        return new EMVRemote(input, output, app_output, app_input);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof EMVRemote)) {
            return false;
        }
        EMVRemote eMVRemote = (EMVRemote) other;
        return AbstractC7609s.f(this.input, eMVRemote.input) && AbstractC7609s.f(this.output, eMVRemote.output) && AbstractC7609s.f(this.app_output, eMVRemote.app_output) && AbstractC7609s.f(this.app_input, eMVRemote.app_input);
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
        return "EMVRemote(input=" + this.input + ", output=" + this.output + ", app_output=" + this.app_output + ", app_input=" + this.app_input + ')';
    }
}
