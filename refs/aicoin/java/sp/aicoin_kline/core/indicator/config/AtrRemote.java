package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000.\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0010\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0003\b\u0087\b\u0018\u00002\u00020\u0001:\u0002\u001c\u001dB/\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\b\u0010\tJ\u000b\u0010\u0010\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u0011\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0012\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0013\u001a\u0004\u0018\u00010\u0003HÆ\u0003J9\u0010\u0014\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\u0015\u001a\u00020\u00162\b\u0010\u0017\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0018\u001a\u00020\u0019HÖ\u0001J\t\u0010\u001a\u001a\u00020\u001bHÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\n\u0010\u000bR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\f\u0010\rR\u0013\u0010\u0006\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\rR\u0013\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u000f\u0010\u000b¨\u0006\u001e"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/AtrRemote;", "", "input", "Lsp/aicoin_kline/core/indicator/config/AtrRemote$Input;", "output", "Lsp/aicoin_kline/core/indicator/config/AtrRemote$Output;", "app_output", "app_input", "<init>", "(Lsp/aicoin_kline/core/indicator/config/AtrRemote$Input;Lsp/aicoin_kline/core/indicator/config/AtrRemote$Output;Lsp/aicoin_kline/core/indicator/config/AtrRemote$Output;Lsp/aicoin_kline/core/indicator/config/AtrRemote$Input;)V", "getInput", "()Lsp/aicoin_kline/core/indicator/config/AtrRemote$Input;", "getOutput", "()Lsp/aicoin_kline/core/indicator/config/AtrRemote$Output;", "getApp_output", "getApp_input", "component1", "component2", "component3", "component4", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Input", "Output", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class AtrRemote {
    private final Input app_input;
    private final Output app_output;
    private final Input input;
    private final Output output;

    @Keep
    @Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0002\b\t\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0010\u000e\n\u0000\b\u0087\b\u0018\u00002\u00020\u0001B\u0011\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0004\u0010\u0005J\u0010\u0010\t\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0007J\u001a\u0010\n\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003HÆ\u0001¢\u0006\u0002\u0010\u000bJ\u0013\u0010\f\u001a\u00020\r2\b\u0010\u000e\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u000f\u001a\u00020\u0003HÖ\u0001J\t\u0010\u0010\u001a\u00020\u0011HÖ\u0001R\u0015\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\b\u001a\u0004\b\u0006\u0010\u0007¨\u0006\u0012"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/AtrRemote$Input;", "", "cc", "", "<init>", "(Ljava/lang/Integer;)V", "getCc", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "component1", "copy", "(Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/AtrRemote$Input;", "equals", "", "other", "hashCode", "toString", "", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Input {
        private final Integer cc;

        public Input(Integer num) {
            this.cc = num;
        }

        public static /* synthetic */ Input copy$default(Input input, Integer num, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                num = input.cc;
            }
            return input.copy(num);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Integer getCc() {
            return this.cc;
        }

        public final Input copy(Integer cc2) {
            return new Input(cc2);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            return (other instanceof Input) && AbstractC7609s.f(this.cc, ((Input) other).cc);
        }

        public final Integer getCc() {
            return this.cc;
        }

        public int hashCode() {
            Integer num = this.cc;
            if (num == null) {
                return 0;
            }
            return num.hashCode();
        }

        public String toString() {
            return kk.b.a(new StringBuilder("Input(cc="), this.cc, ')');
        }
    }

    @Keep
    @Metadata(d1 = {"\u0000\u001e\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\b\n\u0002\b\u0014\b\u0087\b\u0018\u00002\u00020\u0001B+\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0007¢\u0006\u0004\b\b\u0010\tJ\u0010\u0010\u0012\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u000bJ\u000b\u0010\u0013\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010\u0014\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0010J2\u0010\u0015\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0007HÆ\u0001¢\u0006\u0002\u0010\u0016J\u0013\u0010\u0017\u001a\u00020\u00032\b\u0010\u0018\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0019\u001a\u00020\u0007HÖ\u0001J\t\u0010\u001a\u001a\u00020\u0005HÖ\u0001R\u001a\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\f\u001a\u0004\b\n\u0010\u000bR\u0018\u0010\u0004\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\r\u0010\u000eR\u001a\u0010\u0006\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0011\u001a\u0004\b\u000f\u0010\u0010¨\u0006\u001b"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/AtrRemote$Output;", "", "atrDisabled", "", "atrLineColor", "", "atrLineWidth", "", "<init>", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)V", "getAtrDisabled", "()Ljava/lang/Boolean;", "Ljava/lang/Boolean;", "getAtrLineColor", "()Ljava/lang/String;", "getAtrLineWidth", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "component1", "component2", "component3", "copy", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/AtrRemote$Output;", "equals", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Output {

        @SerializedName("atr_disabled")
        private final Boolean atrDisabled;

        @SerializedName("atr_lineColor")
        private final String atrLineColor;

        @SerializedName("atr_lineWidth")
        private final Integer atrLineWidth;

        public Output() {
            this(null, null, null, 7, null);
        }

        public Output(Boolean bool, String str, Integer num) {
            this.atrDisabled = bool;
            this.atrLineColor = str;
            this.atrLineWidth = num;
        }

        public /* synthetic */ Output(Boolean bool, String str, Integer num, int i10, DefaultConstructorMarker defaultConstructorMarker) {
            this((i10 & 1) != 0 ? null : bool, (i10 & 2) != 0 ? null : str, (i10 & 4) != 0 ? null : num);
        }

        public static /* synthetic */ Output copy$default(Output output, Boolean bool, String str, Integer num, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                bool = output.atrDisabled;
            }
            if ((i10 & 2) != 0) {
                str = output.atrLineColor;
            }
            if ((i10 & 4) != 0) {
                num = output.atrLineWidth;
            }
            return output.copy(bool, str, num);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Boolean getAtrDisabled() {
            return this.atrDisabled;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final String getAtrLineColor() {
            return this.atrLineColor;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final Integer getAtrLineWidth() {
            return this.atrLineWidth;
        }

        public final Output copy(Boolean atrDisabled, String atrLineColor, Integer atrLineWidth) {
            return new Output(atrDisabled, atrLineColor, atrLineWidth);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Output)) {
                return false;
            }
            Output output = (Output) other;
            return AbstractC7609s.f(this.atrDisabled, output.atrDisabled) && AbstractC7609s.f(this.atrLineColor, output.atrLineColor) && AbstractC7609s.f(this.atrLineWidth, output.atrLineWidth);
        }

        public final Boolean getAtrDisabled() {
            return this.atrDisabled;
        }

        public final String getAtrLineColor() {
            return this.atrLineColor;
        }

        public final Integer getAtrLineWidth() {
            return this.atrLineWidth;
        }

        public int hashCode() {
            Boolean bool = this.atrDisabled;
            int iHashCode = (bool == null ? 0 : bool.hashCode()) * 31;
            String str = this.atrLineColor;
            int iHashCode2 = (iHashCode + (str == null ? 0 : str.hashCode())) * 31;
            Integer num = this.atrLineWidth;
            return iHashCode2 + (num != null ? num.hashCode() : 0);
        }

        public String toString() {
            StringBuilder sb2 = new StringBuilder("Output(atrDisabled=");
            sb2.append(this.atrDisabled);
            sb2.append(", atrLineColor=");
            sb2.append(this.atrLineColor);
            sb2.append(", atrLineWidth=");
            return kk.b.a(sb2, this.atrLineWidth, ')');
        }
    }

    public AtrRemote(Input input, Output output, Output output2, Input input2) {
        this.input = input;
        this.output = output;
        this.app_output = output2;
        this.app_input = input2;
    }

    public static /* synthetic */ AtrRemote copy$default(AtrRemote atrRemote, Input input, Output output, Output output2, Input input2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            input = atrRemote.input;
        }
        if ((i10 & 2) != 0) {
            output = atrRemote.output;
        }
        if ((i10 & 4) != 0) {
            output2 = atrRemote.app_output;
        }
        if ((i10 & 8) != 0) {
            input2 = atrRemote.app_input;
        }
        return atrRemote.copy(input, output, output2, input2);
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

    public final AtrRemote copy(Input input, Output output, Output app_output, Input app_input) {
        return new AtrRemote(input, output, app_output, app_input);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof AtrRemote)) {
            return false;
        }
        AtrRemote atrRemote = (AtrRemote) other;
        return AbstractC7609s.f(this.input, atrRemote.input) && AbstractC7609s.f(this.output, atrRemote.output) && AbstractC7609s.f(this.app_output, atrRemote.app_output) && AbstractC7609s.f(this.app_input, atrRemote.app_input);
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
        return "AtrRemote(input=" + this.input + ", output=" + this.output + ", app_output=" + this.app_output + ", app_input=" + this.app_input + ')';
    }
}
