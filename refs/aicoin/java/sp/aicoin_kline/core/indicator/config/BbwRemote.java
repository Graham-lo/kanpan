package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000.\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0010\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0003\b\u0087\b\u0018\u00002\u00020\u0001:\u0002\u001c\u001dB/\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\b\u0010\tJ\u000b\u0010\u0010\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u0011\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0012\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0013\u001a\u0004\u0018\u00010\u0003HÆ\u0003J9\u0010\u0014\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\u0015\u001a\u00020\u00162\b\u0010\u0017\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0018\u001a\u00020\u0019HÖ\u0001J\t\u0010\u001a\u001a\u00020\u001bHÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\n\u0010\u000bR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\f\u0010\rR\u0013\u0010\u0006\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\rR\u0013\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u000f\u0010\u000b¨\u0006\u001e"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/BbwRemote;", "", "input", "Lsp/aicoin_kline/core/indicator/config/BbwRemote$Input;", "output", "Lsp/aicoin_kline/core/indicator/config/BbwRemote$Output;", "app_output", "app_input", "<init>", "(Lsp/aicoin_kline/core/indicator/config/BbwRemote$Input;Lsp/aicoin_kline/core/indicator/config/BbwRemote$Output;Lsp/aicoin_kline/core/indicator/config/BbwRemote$Output;Lsp/aicoin_kline/core/indicator/config/BbwRemote$Input;)V", "getInput", "()Lsp/aicoin_kline/core/indicator/config/BbwRemote$Input;", "getOutput", "()Lsp/aicoin_kline/core/indicator/config/BbwRemote$Output;", "getApp_output", "getApp_input", "component1", "component2", "component3", "component4", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Input", "Output", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class BbwRemote {
    private final Input app_input;
    private final Output app_output;
    private final Input input;
    private final Output output;

    @Keep
    @Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0002\b\f\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0010\u000e\n\u0000\b\u0087\b\u0018\u00002\u00020\u0001B\u001b\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0005\u0010\u0006J\u0010\u0010\u000b\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\bJ\u0010\u0010\f\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\bJ&\u0010\r\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0003HÆ\u0001¢\u0006\u0002\u0010\u000eJ\u0013\u0010\u000f\u001a\u00020\u00102\b\u0010\u0011\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0012\u001a\u00020\u0003HÖ\u0001J\t\u0010\u0013\u001a\u00020\u0014HÖ\u0001R\u0015\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\t\u001a\u0004\b\u0007\u0010\bR\u0015\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\t\u001a\u0004\b\n\u0010\b¨\u0006\u0015"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/BbwRemote$Input;", "", "cc", "", "sd", "<init>", "(Ljava/lang/Integer;Ljava/lang/Integer;)V", "getCc", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getSd", "component1", "component2", "copy", "(Ljava/lang/Integer;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/BbwRemote$Input;", "equals", "", "other", "hashCode", "toString", "", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Input {
        private final Integer cc;
        private final Integer sd;

        public Input(Integer num, Integer num2) {
            this.cc = num;
            this.sd = num2;
        }

        public static /* synthetic */ Input copy$default(Input input, Integer num, Integer num2, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                num = input.cc;
            }
            if ((i10 & 2) != 0) {
                num2 = input.sd;
            }
            return input.copy(num, num2);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Integer getCc() {
            return this.cc;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final Integer getSd() {
            return this.sd;
        }

        public final Input copy(Integer cc2, Integer sd2) {
            return new Input(cc2, sd2);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Input)) {
                return false;
            }
            Input input = (Input) other;
            return AbstractC7609s.f(this.cc, input.cc) && AbstractC7609s.f(this.sd, input.sd);
        }

        public final Integer getCc() {
            return this.cc;
        }

        public final Integer getSd() {
            return this.sd;
        }

        public int hashCode() {
            Integer num = this.cc;
            int iHashCode = (num == null ? 0 : num.hashCode()) * 31;
            Integer num2 = this.sd;
            return iHashCode + (num2 != null ? num2.hashCode() : 0);
        }

        public String toString() {
            StringBuilder sb2 = new StringBuilder("Input(cc=");
            sb2.append(this.cc);
            sb2.append(", sd=");
            return kk.b.a(sb2, this.sd, ')');
        }
    }

    @Keep
    @Metadata(d1 = {"\u0000\u001e\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\b\n\u0002\b\u0014\b\u0087\b\u0018\u00002\u00020\u0001B+\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0007¢\u0006\u0004\b\b\u0010\tJ\u0010\u0010\u0012\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u000bJ\u000b\u0010\u0013\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010\u0014\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0010J2\u0010\u0015\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0007HÆ\u0001¢\u0006\u0002\u0010\u0016J\u0013\u0010\u0017\u001a\u00020\u00032\b\u0010\u0018\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0019\u001a\u00020\u0007HÖ\u0001J\t\u0010\u001a\u001a\u00020\u0005HÖ\u0001R\u001a\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\f\u001a\u0004\b\n\u0010\u000bR\u0018\u0010\u0004\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\r\u0010\u000eR\u001a\u0010\u0006\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0011\u001a\u0004\b\u000f\u0010\u0010¨\u0006\u001b"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/BbwRemote$Output;", "", "bbwDisabled", "", "bbwLineColor", "", "bbwLineWidth", "", "<init>", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)V", "getBbwDisabled", "()Ljava/lang/Boolean;", "Ljava/lang/Boolean;", "getBbwLineColor", "()Ljava/lang/String;", "getBbwLineWidth", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "component1", "component2", "component3", "copy", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/BbwRemote$Output;", "equals", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Output {

        @SerializedName("bbw_disabled")
        private final Boolean bbwDisabled;

        @SerializedName("bbw_lineColor")
        private final String bbwLineColor;

        @SerializedName("bbw_lineWidth")
        private final Integer bbwLineWidth;

        public Output() {
            this(null, null, null, 7, null);
        }

        public Output(Boolean bool, String str, Integer num) {
            this.bbwDisabled = bool;
            this.bbwLineColor = str;
            this.bbwLineWidth = num;
        }

        public /* synthetic */ Output(Boolean bool, String str, Integer num, int i10, DefaultConstructorMarker defaultConstructorMarker) {
            this((i10 & 1) != 0 ? null : bool, (i10 & 2) != 0 ? null : str, (i10 & 4) != 0 ? null : num);
        }

        public static /* synthetic */ Output copy$default(Output output, Boolean bool, String str, Integer num, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                bool = output.bbwDisabled;
            }
            if ((i10 & 2) != 0) {
                str = output.bbwLineColor;
            }
            if ((i10 & 4) != 0) {
                num = output.bbwLineWidth;
            }
            return output.copy(bool, str, num);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Boolean getBbwDisabled() {
            return this.bbwDisabled;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final String getBbwLineColor() {
            return this.bbwLineColor;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final Integer getBbwLineWidth() {
            return this.bbwLineWidth;
        }

        public final Output copy(Boolean bbwDisabled, String bbwLineColor, Integer bbwLineWidth) {
            return new Output(bbwDisabled, bbwLineColor, bbwLineWidth);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Output)) {
                return false;
            }
            Output output = (Output) other;
            return AbstractC7609s.f(this.bbwDisabled, output.bbwDisabled) && AbstractC7609s.f(this.bbwLineColor, output.bbwLineColor) && AbstractC7609s.f(this.bbwLineWidth, output.bbwLineWidth);
        }

        public final Boolean getBbwDisabled() {
            return this.bbwDisabled;
        }

        public final String getBbwLineColor() {
            return this.bbwLineColor;
        }

        public final Integer getBbwLineWidth() {
            return this.bbwLineWidth;
        }

        public int hashCode() {
            Boolean bool = this.bbwDisabled;
            int iHashCode = (bool == null ? 0 : bool.hashCode()) * 31;
            String str = this.bbwLineColor;
            int iHashCode2 = (iHashCode + (str == null ? 0 : str.hashCode())) * 31;
            Integer num = this.bbwLineWidth;
            return iHashCode2 + (num != null ? num.hashCode() : 0);
        }

        public String toString() {
            StringBuilder sb2 = new StringBuilder("Output(bbwDisabled=");
            sb2.append(this.bbwDisabled);
            sb2.append(", bbwLineColor=");
            sb2.append(this.bbwLineColor);
            sb2.append(", bbwLineWidth=");
            return kk.b.a(sb2, this.bbwLineWidth, ')');
        }
    }

    public BbwRemote(Input input, Output output, Output output2, Input input2) {
        this.input = input;
        this.output = output;
        this.app_output = output2;
        this.app_input = input2;
    }

    public static /* synthetic */ BbwRemote copy$default(BbwRemote bbwRemote, Input input, Output output, Output output2, Input input2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            input = bbwRemote.input;
        }
        if ((i10 & 2) != 0) {
            output = bbwRemote.output;
        }
        if ((i10 & 4) != 0) {
            output2 = bbwRemote.app_output;
        }
        if ((i10 & 8) != 0) {
            input2 = bbwRemote.app_input;
        }
        return bbwRemote.copy(input, output, output2, input2);
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

    public final BbwRemote copy(Input input, Output output, Output app_output, Input app_input) {
        return new BbwRemote(input, output, app_output, app_input);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof BbwRemote)) {
            return false;
        }
        BbwRemote bbwRemote = (BbwRemote) other;
        return AbstractC7609s.f(this.input, bbwRemote.input) && AbstractC7609s.f(this.output, bbwRemote.output) && AbstractC7609s.f(this.app_output, bbwRemote.app_output) && AbstractC7609s.f(this.app_input, bbwRemote.app_input);
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
        return "BbwRemote(input=" + this.input + ", output=" + this.output + ", app_output=" + this.app_output + ", app_input=" + this.app_input + ')';
    }
}
