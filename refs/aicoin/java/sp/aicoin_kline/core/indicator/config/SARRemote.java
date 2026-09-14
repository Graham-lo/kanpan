package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000.\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0010\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0003\b\u0087\b\u0018\u00002\u00020\u0001:\u0002\u001c\u001dB/\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\b\u0010\tJ\u000b\u0010\u0010\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u0011\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0012\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0013\u001a\u0004\u0018\u00010\u0003HÆ\u0003J9\u0010\u0014\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\u0015\u001a\u00020\u00162\b\u0010\u0017\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0018\u001a\u00020\u0019HÖ\u0001J\t\u0010\u001a\u001a\u00020\u001bHÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\n\u0010\u000bR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\f\u0010\rR\u0013\u0010\u0006\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\rR\u0013\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u000f\u0010\u000b¨\u0006\u001e"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/SARRemote;", "", "input", "Lsp/aicoin_kline/core/indicator/config/SARRemote$Input;", "output", "Lsp/aicoin_kline/core/indicator/config/SARRemote$Output;", "app_output", "app_input", "<init>", "(Lsp/aicoin_kline/core/indicator/config/SARRemote$Input;Lsp/aicoin_kline/core/indicator/config/SARRemote$Output;Lsp/aicoin_kline/core/indicator/config/SARRemote$Output;Lsp/aicoin_kline/core/indicator/config/SARRemote$Input;)V", "getInput", "()Lsp/aicoin_kline/core/indicator/config/SARRemote$Input;", "getOutput", "()Lsp/aicoin_kline/core/indicator/config/SARRemote$Output;", "getApp_output", "getApp_input", "component1", "component2", "component3", "component4", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Input", "Output", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class SARRemote {
    private final Input app_input;
    private final Output app_output;
    private final Input input;
    private final Output output;

    @Keep
    @Metadata(d1 = {"\u0000\"\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000e\n\u0002\b\n\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0002\b\u0002\b\u0087\b\u0018\u00002\u00020\u0001B\u001b\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0005\u0010\u0006J\u000b\u0010\n\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u000b\u001a\u0004\u0018\u00010\u0003HÆ\u0003J!\u0010\f\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\r\u001a\u00020\u000e2\b\u0010\u000f\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0010\u001a\u00020\u0011HÖ\u0001J\t\u0010\u0012\u001a\u00020\u0003HÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0007\u0010\bR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\t\u0010\b¨\u0006\u0013"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/SARRemote$Input;", "", "af", "", "ep", "<init>", "(Ljava/lang/String;Ljava/lang/String;)V", "getAf", "()Ljava/lang/String;", "getEp", "component1", "component2", "copy", "equals", "", "other", "hashCode", "", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Input {
        private final String af;
        private final String ep;

        public Input(String str, String str2) {
            this.af = str;
            this.ep = str2;
        }

        public static /* synthetic */ Input copy$default(Input input, String str, String str2, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                str = input.af;
            }
            if ((i10 & 2) != 0) {
                str2 = input.ep;
            }
            return input.copy(str, str2);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final String getAf() {
            return this.af;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final String getEp() {
            return this.ep;
        }

        public final Input copy(String af2, String ep) {
            return new Input(af2, ep);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Input)) {
                return false;
            }
            Input input = (Input) other;
            return AbstractC7609s.f(this.af, input.af) && AbstractC7609s.f(this.ep, input.ep);
        }

        public final String getAf() {
            return this.af;
        }

        public final String getEp() {
            return this.ep;
        }

        public int hashCode() {
            String str = this.af;
            int iHashCode = (str == null ? 0 : str.hashCode()) * 31;
            String str2 = this.ep;
            return iHashCode + (str2 != null ? str2.hashCode() : 0);
        }

        public String toString() {
            StringBuilder sb2 = new StringBuilder("Input(af=");
            sb2.append(this.af);
            sb2.append(", ep=");
            return kk.h.a(sb2, this.ep, ')');
        }
    }

    @Keep
    @Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\u000b\n\u0002\b\u0011\n\u0002\u0010\b\n\u0002\b\u0002\b\u0087\b\u0018\u00002\u00020\u0001B+\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0005¢\u0006\u0004\b\u0007\u0010\bJ\u000b\u0010\u000f\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0010\u0010\u0010\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\fJ\u0010\u0010\u0011\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\fJ2\u0010\u0012\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0005HÆ\u0001¢\u0006\u0002\u0010\u0013J\u0013\u0010\u0014\u001a\u00020\u00052\b\u0010\u0015\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0016\u001a\u00020\u0017HÖ\u0001J\t\u0010\u0018\u001a\u00020\u0003HÖ\u0001R\u0018\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\t\u0010\nR\u001a\u0010\u0004\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\r\u001a\u0004\b\u000b\u0010\fR\u001a\u0010\u0006\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\r\u001a\u0004\b\u000e\u0010\f¨\u0006\u0019"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/SARRemote$Output;", "", "sarColor", "", "sarDisabled", "", "sarFill", "<init>", "(Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/Boolean;)V", "getSarColor", "()Ljava/lang/String;", "getSarDisabled", "()Ljava/lang/Boolean;", "Ljava/lang/Boolean;", "getSarFill", "component1", "component2", "component3", "copy", "(Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/Boolean;)Lsp/aicoin_kline/core/indicator/config/SARRemote$Output;", "equals", "other", "hashCode", "", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Output {

        @SerializedName("sar_color")
        private final String sarColor;

        @SerializedName("sar_disabled")
        private final Boolean sarDisabled;

        @SerializedName("sar_fill")
        private final Boolean sarFill;

        public Output() {
            this(null, null, null, 7, null);
        }

        public Output(String str, Boolean bool, Boolean bool2) {
            this.sarColor = str;
            this.sarDisabled = bool;
            this.sarFill = bool2;
        }

        public /* synthetic */ Output(String str, Boolean bool, Boolean bool2, int i10, DefaultConstructorMarker defaultConstructorMarker) {
            this((i10 & 1) != 0 ? null : str, (i10 & 2) != 0 ? null : bool, (i10 & 4) != 0 ? null : bool2);
        }

        public static /* synthetic */ Output copy$default(Output output, String str, Boolean bool, Boolean bool2, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                str = output.sarColor;
            }
            if ((i10 & 2) != 0) {
                bool = output.sarDisabled;
            }
            if ((i10 & 4) != 0) {
                bool2 = output.sarFill;
            }
            return output.copy(str, bool, bool2);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final String getSarColor() {
            return this.sarColor;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final Boolean getSarDisabled() {
            return this.sarDisabled;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final Boolean getSarFill() {
            return this.sarFill;
        }

        public final Output copy(String sarColor, Boolean sarDisabled, Boolean sarFill) {
            return new Output(sarColor, sarDisabled, sarFill);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Output)) {
                return false;
            }
            Output output = (Output) other;
            return AbstractC7609s.f(this.sarColor, output.sarColor) && AbstractC7609s.f(this.sarDisabled, output.sarDisabled) && AbstractC7609s.f(this.sarFill, output.sarFill);
        }

        public final String getSarColor() {
            return this.sarColor;
        }

        public final Boolean getSarDisabled() {
            return this.sarDisabled;
        }

        public final Boolean getSarFill() {
            return this.sarFill;
        }

        public int hashCode() {
            String str = this.sarColor;
            int iHashCode = (str == null ? 0 : str.hashCode()) * 31;
            Boolean bool = this.sarDisabled;
            int iHashCode2 = (iHashCode + (bool == null ? 0 : bool.hashCode())) * 31;
            Boolean bool2 = this.sarFill;
            return iHashCode2 + (bool2 != null ? bool2.hashCode() : 0);
        }

        public String toString() {
            return "Output(sarColor=" + this.sarColor + ", sarDisabled=" + this.sarDisabled + ", sarFill=" + this.sarFill + ')';
        }
    }

    public SARRemote(Input input, Output output, Output output2, Input input2) {
        this.input = input;
        this.output = output;
        this.app_output = output2;
        this.app_input = input2;
    }

    public static /* synthetic */ SARRemote copy$default(SARRemote sARRemote, Input input, Output output, Output output2, Input input2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            input = sARRemote.input;
        }
        if ((i10 & 2) != 0) {
            output = sARRemote.output;
        }
        if ((i10 & 4) != 0) {
            output2 = sARRemote.app_output;
        }
        if ((i10 & 8) != 0) {
            input2 = sARRemote.app_input;
        }
        return sARRemote.copy(input, output, output2, input2);
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

    public final SARRemote copy(Input input, Output output, Output app_output, Input app_input) {
        return new SARRemote(input, output, app_output, app_input);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof SARRemote)) {
            return false;
        }
        SARRemote sARRemote = (SARRemote) other;
        return AbstractC7609s.f(this.input, sARRemote.input) && AbstractC7609s.f(this.output, sARRemote.output) && AbstractC7609s.f(this.app_output, sARRemote.app_output) && AbstractC7609s.f(this.app_input, sARRemote.app_input);
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
        return "SARRemote(input=" + this.input + ", output=" + this.output + ", app_output=" + this.app_output + ", app_input=" + this.app_input + ')';
    }
}
