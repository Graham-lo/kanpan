package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000.\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0010\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0003\b\u0087\b\u0018\u00002\u00020\u0001:\u0002\u001c\u001dB/\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\b\u0010\tJ\u000b\u0010\u0010\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u0011\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0012\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0013\u001a\u0004\u0018\u00010\u0003HÆ\u0003J9\u0010\u0014\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\u0015\u001a\u00020\u00162\b\u0010\u0017\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0018\u001a\u00020\u0019HÖ\u0001J\t\u0010\u001a\u001a\u00020\u001bHÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\n\u0010\u000bR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\f\u0010\rR\u0013\u0010\u0006\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\rR\u0013\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u000f\u0010\u000b¨\u0006\u001e"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/TrixRemote;", "", "input", "Lsp/aicoin_kline/core/indicator/config/TrixRemote$Input;", "output", "Lsp/aicoin_kline/core/indicator/config/TrixRemote$Output;", "app_output", "app_input", "<init>", "(Lsp/aicoin_kline/core/indicator/config/TrixRemote$Input;Lsp/aicoin_kline/core/indicator/config/TrixRemote$Output;Lsp/aicoin_kline/core/indicator/config/TrixRemote$Output;Lsp/aicoin_kline/core/indicator/config/TrixRemote$Input;)V", "getInput", "()Lsp/aicoin_kline/core/indicator/config/TrixRemote$Input;", "getOutput", "()Lsp/aicoin_kline/core/indicator/config/TrixRemote$Output;", "getApp_output", "getApp_input", "component1", "component2", "component3", "component4", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Input", "Output", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class TrixRemote {
    private final Input app_input;
    private final Output app_output;
    private final Input input;
    private final Output output;

    @Keep
    @Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0002\b\f\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0010\u000e\n\u0000\b\u0087\b\u0018\u00002\u00020\u0001B\u001b\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0005\u0010\u0006J\u0010\u0010\u000b\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\bJ\u0010\u0010\f\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\bJ&\u0010\r\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0003HÆ\u0001¢\u0006\u0002\u0010\u000eJ\u0013\u0010\u000f\u001a\u00020\u00102\b\u0010\u0011\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0012\u001a\u00020\u0003HÖ\u0001J\t\u0010\u0013\u001a\u00020\u0014HÖ\u0001R\u0015\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\t\u001a\u0004\b\u0007\u0010\bR\u0015\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\t\u001a\u0004\b\n\u0010\b¨\u0006\u0015"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/TrixRemote$Input;", "", "mac1", "", "mac2", "<init>", "(Ljava/lang/Integer;Ljava/lang/Integer;)V", "getMac1", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getMac2", "component1", "component2", "copy", "(Ljava/lang/Integer;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/TrixRemote$Input;", "equals", "", "other", "hashCode", "toString", "", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
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
    @Metadata(d1 = {"\u0000\u001e\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\b\n\u0002\b\u001d\b\u0087\b\u0018\u00002\u00020\u0001BO\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u0007¢\u0006\u0004\b\u000b\u0010\fJ\u0010\u0010\u0018\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u000eJ\u000b\u0010\u0019\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010\u001a\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0013J\u0010\u0010\u001b\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u000eJ\u000b\u0010\u001c\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010\u001d\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0013JV\u0010\u001e\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u0007HÆ\u0001¢\u0006\u0002\u0010\u001fJ\u0013\u0010 \u001a\u00020\u00032\b\u0010!\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\"\u001a\u00020\u0007HÖ\u0001J\t\u0010#\u001a\u00020\u0005HÖ\u0001R\u001a\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u000f\u001a\u0004\b\r\u0010\u000eR\u0018\u0010\u0004\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0010\u0010\u0011R\u001a\u0010\u0006\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0014\u001a\u0004\b\u0012\u0010\u0013R\u001a\u0010\b\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u000f\u001a\u0004\b\u0015\u0010\u000eR\u0018\u0010\t\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0016\u0010\u0011R\u001a\u0010\n\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0014\u001a\u0004\b\u0017\u0010\u0013¨\u0006$"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/TrixRemote$Output;", "", "maTrixDisabled", "", "maTrixLineColor", "", "maTrixLineWidth", "", "trixDisabled", "trixLineColor", "trixLineWidth", "<init>", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)V", "getMaTrixDisabled", "()Ljava/lang/Boolean;", "Ljava/lang/Boolean;", "getMaTrixLineColor", "()Ljava/lang/String;", "getMaTrixLineWidth", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getTrixDisabled", "getTrixLineColor", "getTrixLineWidth", "component1", "component2", "component3", "component4", "component5", "component6", "copy", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/TrixRemote$Output;", "equals", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Output {

        @SerializedName("maTrix_disabled")
        private final Boolean maTrixDisabled;

        @SerializedName("maTrix_lineColor")
        private final String maTrixLineColor;

        @SerializedName("maTrix_lineWidth")
        private final Integer maTrixLineWidth;

        @SerializedName("trix_disabled")
        private final Boolean trixDisabled;

        @SerializedName("trix_lineColor")
        private final String trixLineColor;

        @SerializedName("trix_lineWidth")
        private final Integer trixLineWidth;

        public Output() {
            this(null, null, null, null, null, null, 63, null);
        }

        public Output(Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2) {
            this.maTrixDisabled = bool;
            this.maTrixLineColor = str;
            this.maTrixLineWidth = num;
            this.trixDisabled = bool2;
            this.trixLineColor = str2;
            this.trixLineWidth = num2;
        }

        public /* synthetic */ Output(Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2, int i10, DefaultConstructorMarker defaultConstructorMarker) {
            this((i10 & 1) != 0 ? null : bool, (i10 & 2) != 0 ? null : str, (i10 & 4) != 0 ? null : num, (i10 & 8) != 0 ? null : bool2, (i10 & 16) != 0 ? null : str2, (i10 & 32) != 0 ? null : num2);
        }

        public static /* synthetic */ Output copy$default(Output output, Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                bool = output.maTrixDisabled;
            }
            if ((i10 & 2) != 0) {
                str = output.maTrixLineColor;
            }
            if ((i10 & 4) != 0) {
                num = output.maTrixLineWidth;
            }
            if ((i10 & 8) != 0) {
                bool2 = output.trixDisabled;
            }
            if ((i10 & 16) != 0) {
                str2 = output.trixLineColor;
            }
            if ((i10 & 32) != 0) {
                num2 = output.trixLineWidth;
            }
            String str3 = str2;
            Integer num3 = num2;
            return output.copy(bool, str, num, bool2, str3, num3);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Boolean getMaTrixDisabled() {
            return this.maTrixDisabled;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final String getMaTrixLineColor() {
            return this.maTrixLineColor;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final Integer getMaTrixLineWidth() {
            return this.maTrixLineWidth;
        }

        /* JADX INFO: renamed from: component4, reason: from getter */
        public final Boolean getTrixDisabled() {
            return this.trixDisabled;
        }

        /* JADX INFO: renamed from: component5, reason: from getter */
        public final String getTrixLineColor() {
            return this.trixLineColor;
        }

        /* JADX INFO: renamed from: component6, reason: from getter */
        public final Integer getTrixLineWidth() {
            return this.trixLineWidth;
        }

        public final Output copy(Boolean maTrixDisabled, String maTrixLineColor, Integer maTrixLineWidth, Boolean trixDisabled, String trixLineColor, Integer trixLineWidth) {
            return new Output(maTrixDisabled, maTrixLineColor, maTrixLineWidth, trixDisabled, trixLineColor, trixLineWidth);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Output)) {
                return false;
            }
            Output output = (Output) other;
            return AbstractC7609s.f(this.maTrixDisabled, output.maTrixDisabled) && AbstractC7609s.f(this.maTrixLineColor, output.maTrixLineColor) && AbstractC7609s.f(this.maTrixLineWidth, output.maTrixLineWidth) && AbstractC7609s.f(this.trixDisabled, output.trixDisabled) && AbstractC7609s.f(this.trixLineColor, output.trixLineColor) && AbstractC7609s.f(this.trixLineWidth, output.trixLineWidth);
        }

        public final Boolean getMaTrixDisabled() {
            return this.maTrixDisabled;
        }

        public final String getMaTrixLineColor() {
            return this.maTrixLineColor;
        }

        public final Integer getMaTrixLineWidth() {
            return this.maTrixLineWidth;
        }

        public final Boolean getTrixDisabled() {
            return this.trixDisabled;
        }

        public final String getTrixLineColor() {
            return this.trixLineColor;
        }

        public final Integer getTrixLineWidth() {
            return this.trixLineWidth;
        }

        public int hashCode() {
            Boolean bool = this.maTrixDisabled;
            int iHashCode = (bool == null ? 0 : bool.hashCode()) * 31;
            String str = this.maTrixLineColor;
            int iHashCode2 = (iHashCode + (str == null ? 0 : str.hashCode())) * 31;
            Integer num = this.maTrixLineWidth;
            int iHashCode3 = (iHashCode2 + (num == null ? 0 : num.hashCode())) * 31;
            Boolean bool2 = this.trixDisabled;
            int iHashCode4 = (iHashCode3 + (bool2 == null ? 0 : bool2.hashCode())) * 31;
            String str2 = this.trixLineColor;
            int iHashCode5 = (iHashCode4 + (str2 == null ? 0 : str2.hashCode())) * 31;
            Integer num2 = this.trixLineWidth;
            return iHashCode5 + (num2 != null ? num2.hashCode() : 0);
        }

        public String toString() {
            StringBuilder sb2 = new StringBuilder("Output(maTrixDisabled=");
            sb2.append(this.maTrixDisabled);
            sb2.append(", maTrixLineColor=");
            sb2.append(this.maTrixLineColor);
            sb2.append(", maTrixLineWidth=");
            sb2.append(this.maTrixLineWidth);
            sb2.append(", trixDisabled=");
            sb2.append(this.trixDisabled);
            sb2.append(", trixLineColor=");
            sb2.append(this.trixLineColor);
            sb2.append(", trixLineWidth=");
            return kk.b.a(sb2, this.trixLineWidth, ')');
        }
    }

    public TrixRemote(Input input, Output output, Output output2, Input input2) {
        this.input = input;
        this.output = output;
        this.app_output = output2;
        this.app_input = input2;
    }

    public static /* synthetic */ TrixRemote copy$default(TrixRemote trixRemote, Input input, Output output, Output output2, Input input2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            input = trixRemote.input;
        }
        if ((i10 & 2) != 0) {
            output = trixRemote.output;
        }
        if ((i10 & 4) != 0) {
            output2 = trixRemote.app_output;
        }
        if ((i10 & 8) != 0) {
            input2 = trixRemote.app_input;
        }
        return trixRemote.copy(input, output, output2, input2);
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

    public final TrixRemote copy(Input input, Output output, Output app_output, Input app_input) {
        return new TrixRemote(input, output, app_output, app_input);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof TrixRemote)) {
            return false;
        }
        TrixRemote trixRemote = (TrixRemote) other;
        return AbstractC7609s.f(this.input, trixRemote.input) && AbstractC7609s.f(this.output, trixRemote.output) && AbstractC7609s.f(this.app_output, trixRemote.app_output) && AbstractC7609s.f(this.app_input, trixRemote.app_input);
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
        return "TrixRemote(input=" + this.input + ", output=" + this.output + ", app_output=" + this.app_output + ", app_input=" + this.app_input + ')';
    }
}
