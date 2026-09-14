package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000.\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0010\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0003\b\u0087\b\u0018\u00002\u00020\u0001:\u0002\u001c\u001dB/\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\b\u0010\tJ\u000b\u0010\u0010\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u0011\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0012\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0013\u001a\u0004\u0018\u00010\u0003HÆ\u0003J9\u0010\u0014\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\u0015\u001a\u00020\u00162\b\u0010\u0017\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0018\u001a\u00020\u0019HÖ\u0001J\t\u0010\u001a\u001a\u00020\u001bHÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\n\u0010\u000bR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\f\u0010\rR\u0013\u0010\u0006\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\rR\u0013\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u000f\u0010\u000b¨\u0006\u001e"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/ObvRemote;", "", "input", "Lsp/aicoin_kline/core/indicator/config/ObvRemote$Input;", "output", "Lsp/aicoin_kline/core/indicator/config/ObvRemote$Output;", "app_output", "app_input", "<init>", "(Lsp/aicoin_kline/core/indicator/config/ObvRemote$Input;Lsp/aicoin_kline/core/indicator/config/ObvRemote$Output;Lsp/aicoin_kline/core/indicator/config/ObvRemote$Output;Lsp/aicoin_kline/core/indicator/config/ObvRemote$Input;)V", "getInput", "()Lsp/aicoin_kline/core/indicator/config/ObvRemote$Input;", "getOutput", "()Lsp/aicoin_kline/core/indicator/config/ObvRemote$Output;", "getApp_output", "getApp_input", "component1", "component2", "component3", "component4", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Input", "Output", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class ObvRemote {
    private final Input app_input;
    private final Output app_output;
    private final Input input;
    private final Output output;

    @Keep
    @Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0002\b\t\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0010\u000e\n\u0000\b\u0087\b\u0018\u00002\u00020\u0001B\u0011\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0004\u0010\u0005J\u0010\u0010\t\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0007J\u001a\u0010\n\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003HÆ\u0001¢\u0006\u0002\u0010\u000bJ\u0013\u0010\f\u001a\u00020\r2\b\u0010\u000e\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u000f\u001a\u00020\u0003HÖ\u0001J\t\u0010\u0010\u001a\u00020\u0011HÖ\u0001R\u0015\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\b\u001a\u0004\b\u0006\u0010\u0007¨\u0006\u0012"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/ObvRemote$Input;", "", "mac", "", "<init>", "(Ljava/lang/Integer;)V", "getMac", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "component1", "copy", "(Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/ObvRemote$Input;", "equals", "", "other", "hashCode", "toString", "", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Input {
        private final Integer mac;

        public Input(Integer num) {
            this.mac = num;
        }

        public static /* synthetic */ Input copy$default(Input input, Integer num, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                num = input.mac;
            }
            return input.copy(num);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Integer getMac() {
            return this.mac;
        }

        public final Input copy(Integer mac) {
            return new Input(mac);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            return (other instanceof Input) && AbstractC7609s.f(this.mac, ((Input) other).mac);
        }

        public final Integer getMac() {
            return this.mac;
        }

        public int hashCode() {
            Integer num = this.mac;
            if (num == null) {
                return 0;
            }
            return num.hashCode();
        }

        public String toString() {
            return kk.b.a(new StringBuilder("Input(mac="), this.mac, ')');
        }
    }

    @Keep
    @Metadata(d1 = {"\u0000\u001e\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\b\n\u0002\b\u001d\b\u0087\b\u0018\u00002\u00020\u0001BO\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u0007¢\u0006\u0004\b\u000b\u0010\fJ\u0010\u0010\u0018\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u000eJ\u000b\u0010\u0019\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010\u001a\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0013J\u0010\u0010\u001b\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u000eJ\u000b\u0010\u001c\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010\u001d\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0013JV\u0010\u001e\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u0007HÆ\u0001¢\u0006\u0002\u0010\u001fJ\u0013\u0010 \u001a\u00020\u00032\b\u0010!\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\"\u001a\u00020\u0007HÖ\u0001J\t\u0010#\u001a\u00020\u0005HÖ\u0001R\u001a\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u000f\u001a\u0004\b\r\u0010\u000eR\u0018\u0010\u0004\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0010\u0010\u0011R\u001a\u0010\u0006\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0014\u001a\u0004\b\u0012\u0010\u0013R\u001a\u0010\b\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u000f\u001a\u0004\b\u0015\u0010\u000eR\u0018\u0010\t\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0016\u0010\u0011R\u001a\u0010\n\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0014\u001a\u0004\b\u0017\u0010\u0013¨\u0006$"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/ObvRemote$Output;", "", "maObvDisabled", "", "maObvLineColor", "", "maObvLineWidth", "", "obvDisabled", "obvLineColor", "obvLineWidth", "<init>", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)V", "getMaObvDisabled", "()Ljava/lang/Boolean;", "Ljava/lang/Boolean;", "getMaObvLineColor", "()Ljava/lang/String;", "getMaObvLineWidth", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getObvDisabled", "getObvLineColor", "getObvLineWidth", "component1", "component2", "component3", "component4", "component5", "component6", "copy", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/ObvRemote$Output;", "equals", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Output {

        @SerializedName("maObv_disabled")
        private final Boolean maObvDisabled;

        @SerializedName("maObv_lineColor")
        private final String maObvLineColor;

        @SerializedName("maObv_lineWidth")
        private final Integer maObvLineWidth;

        @SerializedName("obv_disabled")
        private final Boolean obvDisabled;

        @SerializedName("obv_lineColor")
        private final String obvLineColor;

        @SerializedName("obv_lineWidth")
        private final Integer obvLineWidth;

        public Output() {
            this(null, null, null, null, null, null, 63, null);
        }

        public Output(Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2) {
            this.maObvDisabled = bool;
            this.maObvLineColor = str;
            this.maObvLineWidth = num;
            this.obvDisabled = bool2;
            this.obvLineColor = str2;
            this.obvLineWidth = num2;
        }

        public /* synthetic */ Output(Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2, int i10, DefaultConstructorMarker defaultConstructorMarker) {
            this((i10 & 1) != 0 ? null : bool, (i10 & 2) != 0 ? null : str, (i10 & 4) != 0 ? null : num, (i10 & 8) != 0 ? null : bool2, (i10 & 16) != 0 ? null : str2, (i10 & 32) != 0 ? null : num2);
        }

        public static /* synthetic */ Output copy$default(Output output, Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                bool = output.maObvDisabled;
            }
            if ((i10 & 2) != 0) {
                str = output.maObvLineColor;
            }
            if ((i10 & 4) != 0) {
                num = output.maObvLineWidth;
            }
            if ((i10 & 8) != 0) {
                bool2 = output.obvDisabled;
            }
            if ((i10 & 16) != 0) {
                str2 = output.obvLineColor;
            }
            if ((i10 & 32) != 0) {
                num2 = output.obvLineWidth;
            }
            String str3 = str2;
            Integer num3 = num2;
            return output.copy(bool, str, num, bool2, str3, num3);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Boolean getMaObvDisabled() {
            return this.maObvDisabled;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final String getMaObvLineColor() {
            return this.maObvLineColor;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final Integer getMaObvLineWidth() {
            return this.maObvLineWidth;
        }

        /* JADX INFO: renamed from: component4, reason: from getter */
        public final Boolean getObvDisabled() {
            return this.obvDisabled;
        }

        /* JADX INFO: renamed from: component5, reason: from getter */
        public final String getObvLineColor() {
            return this.obvLineColor;
        }

        /* JADX INFO: renamed from: component6, reason: from getter */
        public final Integer getObvLineWidth() {
            return this.obvLineWidth;
        }

        public final Output copy(Boolean maObvDisabled, String maObvLineColor, Integer maObvLineWidth, Boolean obvDisabled, String obvLineColor, Integer obvLineWidth) {
            return new Output(maObvDisabled, maObvLineColor, maObvLineWidth, obvDisabled, obvLineColor, obvLineWidth);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Output)) {
                return false;
            }
            Output output = (Output) other;
            return AbstractC7609s.f(this.maObvDisabled, output.maObvDisabled) && AbstractC7609s.f(this.maObvLineColor, output.maObvLineColor) && AbstractC7609s.f(this.maObvLineWidth, output.maObvLineWidth) && AbstractC7609s.f(this.obvDisabled, output.obvDisabled) && AbstractC7609s.f(this.obvLineColor, output.obvLineColor) && AbstractC7609s.f(this.obvLineWidth, output.obvLineWidth);
        }

        public final Boolean getMaObvDisabled() {
            return this.maObvDisabled;
        }

        public final String getMaObvLineColor() {
            return this.maObvLineColor;
        }

        public final Integer getMaObvLineWidth() {
            return this.maObvLineWidth;
        }

        public final Boolean getObvDisabled() {
            return this.obvDisabled;
        }

        public final String getObvLineColor() {
            return this.obvLineColor;
        }

        public final Integer getObvLineWidth() {
            return this.obvLineWidth;
        }

        public int hashCode() {
            Boolean bool = this.maObvDisabled;
            int iHashCode = (bool == null ? 0 : bool.hashCode()) * 31;
            String str = this.maObvLineColor;
            int iHashCode2 = (iHashCode + (str == null ? 0 : str.hashCode())) * 31;
            Integer num = this.maObvLineWidth;
            int iHashCode3 = (iHashCode2 + (num == null ? 0 : num.hashCode())) * 31;
            Boolean bool2 = this.obvDisabled;
            int iHashCode4 = (iHashCode3 + (bool2 == null ? 0 : bool2.hashCode())) * 31;
            String str2 = this.obvLineColor;
            int iHashCode5 = (iHashCode4 + (str2 == null ? 0 : str2.hashCode())) * 31;
            Integer num2 = this.obvLineWidth;
            return iHashCode5 + (num2 != null ? num2.hashCode() : 0);
        }

        public String toString() {
            StringBuilder sb2 = new StringBuilder("Output(maObvDisabled=");
            sb2.append(this.maObvDisabled);
            sb2.append(", maObvLineColor=");
            sb2.append(this.maObvLineColor);
            sb2.append(", maObvLineWidth=");
            sb2.append(this.maObvLineWidth);
            sb2.append(", obvDisabled=");
            sb2.append(this.obvDisabled);
            sb2.append(", obvLineColor=");
            sb2.append(this.obvLineColor);
            sb2.append(", obvLineWidth=");
            return kk.b.a(sb2, this.obvLineWidth, ')');
        }
    }

    public ObvRemote(Input input, Output output, Output output2, Input input2) {
        this.input = input;
        this.output = output;
        this.app_output = output2;
        this.app_input = input2;
    }

    public static /* synthetic */ ObvRemote copy$default(ObvRemote obvRemote, Input input, Output output, Output output2, Input input2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            input = obvRemote.input;
        }
        if ((i10 & 2) != 0) {
            output = obvRemote.output;
        }
        if ((i10 & 4) != 0) {
            output2 = obvRemote.app_output;
        }
        if ((i10 & 8) != 0) {
            input2 = obvRemote.app_input;
        }
        return obvRemote.copy(input, output, output2, input2);
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

    public final ObvRemote copy(Input input, Output output, Output app_output, Input app_input) {
        return new ObvRemote(input, output, app_output, app_input);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof ObvRemote)) {
            return false;
        }
        ObvRemote obvRemote = (ObvRemote) other;
        return AbstractC7609s.f(this.input, obvRemote.input) && AbstractC7609s.f(this.output, obvRemote.output) && AbstractC7609s.f(this.app_output, obvRemote.app_output) && AbstractC7609s.f(this.app_input, obvRemote.app_input);
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
        return "ObvRemote(input=" + this.input + ", output=" + this.output + ", app_output=" + this.app_output + ", app_input=" + this.app_input + ')';
    }
}
