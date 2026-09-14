package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import java.util.List;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000.\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0010\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0003\b\u0087\b\u0018\u00002\u00020\u0001:\u0002\u001c\u001dB/\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\b\u0010\tJ\u000b\u0010\u0010\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u0011\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0012\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0013\u001a\u0004\u0018\u00010\u0003HÆ\u0003J9\u0010\u0014\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\u0015\u001a\u00020\u00162\b\u0010\u0017\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0018\u001a\u00020\u0019HÖ\u0001J\t\u0010\u001a\u001a\u00020\u001bHÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\n\u0010\u000bR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\f\u0010\rR\u0013\u0010\u0006\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\rR\u0013\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u000f\u0010\u000b¨\u0006\u001e"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/EMARemote;", "", "input", "Lsp/aicoin_kline/core/indicator/config/EMARemote$Input;", "output", "Lsp/aicoin_kline/core/indicator/config/EMARemote$Output;", "app_output", "app_input", "<init>", "(Lsp/aicoin_kline/core/indicator/config/EMARemote$Input;Lsp/aicoin_kline/core/indicator/config/EMARemote$Output;Lsp/aicoin_kline/core/indicator/config/EMARemote$Output;Lsp/aicoin_kline/core/indicator/config/EMARemote$Input;)V", "getInput", "()Lsp/aicoin_kline/core/indicator/config/EMARemote$Input;", "getOutput", "()Lsp/aicoin_kline/core/indicator/config/EMARemote$Output;", "getApp_output", "getApp_input", "component1", "component2", "component3", "component4", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Input", "Output", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class EMARemote {
    private final Input app_input;
    private final Output app_output;
    private final Input input;
    private final Output output;

    @Keep
    @Metadata(d1 = {"\u0000$\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010 \n\u0002\u0010\b\n\u0002\b\u0007\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0010\u000e\n\u0000\b\u0087\b\u0018\u00002\u00020\u0001B\u0017\u0012\u000e\u0010\u0002\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0005\u0010\u0006J\u0011\u0010\t\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u0003HÆ\u0003J\u001b\u0010\n\u001a\u00020\u00002\u0010\b\u0002\u0010\u0002\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\u000b\u001a\u00020\f2\b\u0010\r\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u000e\u001a\u00020\u0004HÖ\u0001J\t\u0010\u000f\u001a\u00020\u0010HÖ\u0001R\u0019\u0010\u0002\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0007\u0010\b¨\u0006\u0011"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/EMARemote$Input;", "", "ema", "", "", "<init>", "(Ljava/util/List;)V", "getEma", "()Ljava/util/List;", "component1", "copy", "equals", "", "other", "hashCode", "toString", "", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Input {
        private final List<Integer> ema;

        public Input(List<Integer> list) {
            this.ema = list;
        }

        /* JADX WARN: Multi-variable type inference failed */
        public static /* synthetic */ Input copy$default(Input input, List list, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                list = input.ema;
            }
            return input.copy(list);
        }

        public final List<Integer> component1() {
            return this.ema;
        }

        public final Input copy(List<Integer> ema) {
            return new Input(ema);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            return (other instanceof Input) && AbstractC7609s.f(this.ema, ((Input) other).ema);
        }

        public final List<Integer> getEma() {
            return this.ema;
        }

        public int hashCode() {
            List<Integer> list = this.ema;
            if (list == null) {
                return 0;
            }
            return list.hashCode();
        }

        public String toString() {
            return "Input(ema=" + this.ema + ')';
        }
    }

    @Keep
    @Metadata(d1 = {"\u0000,\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010 \n\u0002\u0018\u0002\n\u0002\b\u0007\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0002\b\u0087\b\u0018\u00002\u00020\u0001:\u0001\u0012B\u0017\u0012\u000e\u0010\u0002\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0005\u0010\u0006J\u0011\u0010\t\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u0003HÆ\u0003J\u001b\u0010\n\u001a\u00020\u00002\u0010\b\u0002\u0010\u0002\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\u000b\u001a\u00020\f2\b\u0010\r\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u000e\u001a\u00020\u000fHÖ\u0001J\t\u0010\u0010\u001a\u00020\u0011HÖ\u0001R\u0019\u0010\u0002\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0007\u0010\b¨\u0006\u0013"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/EMARemote$Output;", "", "ema", "", "Lsp/aicoin_kline/core/indicator/config/EMARemote$Output$Ema;", "<init>", "(Ljava/util/List;)V", "getEma", "()Ljava/util/List;", "component1", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Ema", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Output {
        private final List<Ema> ema;

        @Keep
        @Metadata(d1 = {"\u0000\u001e\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\b\n\u0002\b\u0014\b\u0087\b\u0018\u00002\u00020\u0001B+\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0007¢\u0006\u0004\b\b\u0010\tJ\u0010\u0010\u0012\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u000bJ\u000b\u0010\u0013\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010\u0014\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0010J2\u0010\u0015\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0007HÆ\u0001¢\u0006\u0002\u0010\u0016J\u0013\u0010\u0017\u001a\u00020\u00032\b\u0010\u0018\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0019\u001a\u00020\u0007HÖ\u0001J\t\u0010\u001a\u001a\u00020\u0005HÖ\u0001R\u001a\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\f\u001a\u0004\b\n\u0010\u000bR\u0018\u0010\u0004\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\r\u0010\u000eR\u001a\u0010\u0006\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0011\u001a\u0004\b\u000f\u0010\u0010¨\u0006\u001b"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/EMARemote$Output$Ema;", "", "emaDisabled", "", "emaLineColor", "", "emaLineWidth", "", "<init>", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)V", "getEmaDisabled", "()Ljava/lang/Boolean;", "Ljava/lang/Boolean;", "getEmaLineColor", "()Ljava/lang/String;", "getEmaLineWidth", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "component1", "component2", "component3", "copy", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/EMARemote$Output$Ema;", "equals", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
        public static final /* data */ class Ema {

            @SerializedName("ema_disabled")
            private final Boolean emaDisabled;

            @SerializedName("ema_lineColor")
            private final String emaLineColor;

            @SerializedName("ema_lineWidth")
            private final Integer emaLineWidth;

            public Ema() {
                this(null, null, null, 7, null);
            }

            public Ema(Boolean bool, String str, Integer num) {
                this.emaDisabled = bool;
                this.emaLineColor = str;
                this.emaLineWidth = num;
            }

            public /* synthetic */ Ema(Boolean bool, String str, Integer num, int i10, DefaultConstructorMarker defaultConstructorMarker) {
                this((i10 & 1) != 0 ? null : bool, (i10 & 2) != 0 ? null : str, (i10 & 4) != 0 ? null : num);
            }

            public static /* synthetic */ Ema copy$default(Ema ema, Boolean bool, String str, Integer num, int i10, Object obj) {
                if ((i10 & 1) != 0) {
                    bool = ema.emaDisabled;
                }
                if ((i10 & 2) != 0) {
                    str = ema.emaLineColor;
                }
                if ((i10 & 4) != 0) {
                    num = ema.emaLineWidth;
                }
                return ema.copy(bool, str, num);
            }

            /* JADX INFO: renamed from: component1, reason: from getter */
            public final Boolean getEmaDisabled() {
                return this.emaDisabled;
            }

            /* JADX INFO: renamed from: component2, reason: from getter */
            public final String getEmaLineColor() {
                return this.emaLineColor;
            }

            /* JADX INFO: renamed from: component3, reason: from getter */
            public final Integer getEmaLineWidth() {
                return this.emaLineWidth;
            }

            public final Ema copy(Boolean emaDisabled, String emaLineColor, Integer emaLineWidth) {
                return new Ema(emaDisabled, emaLineColor, emaLineWidth);
            }

            public boolean equals(Object other) {
                if (this == other) {
                    return true;
                }
                if (!(other instanceof Ema)) {
                    return false;
                }
                Ema ema = (Ema) other;
                return AbstractC7609s.f(this.emaDisabled, ema.emaDisabled) && AbstractC7609s.f(this.emaLineColor, ema.emaLineColor) && AbstractC7609s.f(this.emaLineWidth, ema.emaLineWidth);
            }

            public final Boolean getEmaDisabled() {
                return this.emaDisabled;
            }

            public final String getEmaLineColor() {
                return this.emaLineColor;
            }

            public final Integer getEmaLineWidth() {
                return this.emaLineWidth;
            }

            public int hashCode() {
                Boolean bool = this.emaDisabled;
                int iHashCode = (bool == null ? 0 : bool.hashCode()) * 31;
                String str = this.emaLineColor;
                int iHashCode2 = (iHashCode + (str == null ? 0 : str.hashCode())) * 31;
                Integer num = this.emaLineWidth;
                return iHashCode2 + (num != null ? num.hashCode() : 0);
            }

            public String toString() {
                StringBuilder sb2 = new StringBuilder("Ema(emaDisabled=");
                sb2.append(this.emaDisabled);
                sb2.append(", emaLineColor=");
                sb2.append(this.emaLineColor);
                sb2.append(", emaLineWidth=");
                return kk.b.a(sb2, this.emaLineWidth, ')');
            }
        }

        public Output(List<Ema> list) {
            this.ema = list;
        }

        /* JADX WARN: Multi-variable type inference failed */
        public static /* synthetic */ Output copy$default(Output output, List list, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                list = output.ema;
            }
            return output.copy(list);
        }

        public final List<Ema> component1() {
            return this.ema;
        }

        public final Output copy(List<Ema> ema) {
            return new Output(ema);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            return (other instanceof Output) && AbstractC7609s.f(this.ema, ((Output) other).ema);
        }

        public final List<Ema> getEma() {
            return this.ema;
        }

        public int hashCode() {
            List<Ema> list = this.ema;
            if (list == null) {
                return 0;
            }
            return list.hashCode();
        }

        public String toString() {
            return "Output(ema=" + this.ema + ')';
        }
    }

    public EMARemote(Input input, Output output, Output output2, Input input2) {
        this.input = input;
        this.output = output;
        this.app_output = output2;
        this.app_input = input2;
    }

    public static /* synthetic */ EMARemote copy$default(EMARemote eMARemote, Input input, Output output, Output output2, Input input2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            input = eMARemote.input;
        }
        if ((i10 & 2) != 0) {
            output = eMARemote.output;
        }
        if ((i10 & 4) != 0) {
            output2 = eMARemote.app_output;
        }
        if ((i10 & 8) != 0) {
            input2 = eMARemote.app_input;
        }
        return eMARemote.copy(input, output, output2, input2);
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

    public final EMARemote copy(Input input, Output output, Output app_output, Input app_input) {
        return new EMARemote(input, output, app_output, app_input);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof EMARemote)) {
            return false;
        }
        EMARemote eMARemote = (EMARemote) other;
        return AbstractC7609s.f(this.input, eMARemote.input) && AbstractC7609s.f(this.output, eMARemote.output) && AbstractC7609s.f(this.app_output, eMARemote.app_output) && AbstractC7609s.f(this.app_input, eMARemote.app_input);
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
        return "EMARemote(input=" + this.input + ", output=" + this.output + ", app_output=" + this.app_output + ", app_input=" + this.app_input + ')';
    }
}
