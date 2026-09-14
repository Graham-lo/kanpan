package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import java.util.List;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000.\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0010\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0003\b\u0087\b\u0018\u00002\u00020\u0001:\u0002\u001c\u001dB/\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\b\u0010\tJ\u000b\u0010\u0010\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u0011\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0012\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0013\u001a\u0004\u0018\u00010\u0003HÆ\u0003J9\u0010\u0014\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\u0015\u001a\u00020\u00162\b\u0010\u0017\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0018\u001a\u00020\u0019HÖ\u0001J\t\u0010\u001a\u001a\u00020\u001bHÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\n\u0010\u000bR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\f\u0010\rR\u0013\u0010\u0006\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\rR\u0013\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u000f\u0010\u000b¨\u0006\u001e"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/WRRemote;", "", "input", "Lsp/aicoin_kline/core/indicator/config/WRRemote$Input;", "output", "Lsp/aicoin_kline/core/indicator/config/WRRemote$Output;", "app_output", "app_input", "<init>", "(Lsp/aicoin_kline/core/indicator/config/WRRemote$Input;Lsp/aicoin_kline/core/indicator/config/WRRemote$Output;Lsp/aicoin_kline/core/indicator/config/WRRemote$Output;Lsp/aicoin_kline/core/indicator/config/WRRemote$Input;)V", "getInput", "()Lsp/aicoin_kline/core/indicator/config/WRRemote$Input;", "getOutput", "()Lsp/aicoin_kline/core/indicator/config/WRRemote$Output;", "getApp_output", "getApp_input", "component1", "component2", "component3", "component4", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Input", "Output", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class WRRemote {
    private final Input app_input;
    private final Output app_output;
    private final Input input;
    private final Output output;

    @Keep
    @Metadata(d1 = {"\u0000$\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010 \n\u0002\u0010\b\n\u0002\b\u0007\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0010\u000e\n\u0000\b\u0087\b\u0018\u00002\u00020\u0001B\u0017\u0012\u000e\u0010\u0002\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0005\u0010\u0006J\u0011\u0010\t\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u0003HÆ\u0003J\u001b\u0010\n\u001a\u00020\u00002\u0010\b\u0002\u0010\u0002\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\u000b\u001a\u00020\f2\b\u0010\r\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u000e\u001a\u00020\u0004HÖ\u0001J\t\u0010\u000f\u001a\u00020\u0010HÖ\u0001R\u0019\u0010\u0002\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0007\u0010\b¨\u0006\u0011"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/WRRemote$Input;", "", "wr", "", "", "<init>", "(Ljava/util/List;)V", "getWr", "()Ljava/util/List;", "component1", "copy", "equals", "", "other", "hashCode", "toString", "", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Input {
        private final List<Integer> wr;

        public Input(List<Integer> list) {
            this.wr = list;
        }

        /* JADX WARN: Multi-variable type inference failed */
        public static /* synthetic */ Input copy$default(Input input, List list, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                list = input.wr;
            }
            return input.copy(list);
        }

        public final List<Integer> component1() {
            return this.wr;
        }

        public final Input copy(List<Integer> wr) {
            return new Input(wr);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            return (other instanceof Input) && AbstractC7609s.f(this.wr, ((Input) other).wr);
        }

        public final List<Integer> getWr() {
            return this.wr;
        }

        public int hashCode() {
            List<Integer> list = this.wr;
            if (list == null) {
                return 0;
            }
            return list.hashCode();
        }

        public String toString() {
            return "Input(wr=" + this.wr + ')';
        }
    }

    @Keep
    @Metadata(d1 = {"\u0000,\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010 \n\u0002\u0018\u0002\n\u0002\b\u0007\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0002\b\u0087\b\u0018\u00002\u00020\u0001:\u0001\u0012B\u0017\u0012\u000e\u0010\u0002\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0005\u0010\u0006J\u0011\u0010\t\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u0003HÆ\u0003J\u001b\u0010\n\u001a\u00020\u00002\u0010\b\u0002\u0010\u0002\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\u000b\u001a\u00020\f2\b\u0010\r\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u000e\u001a\u00020\u000fHÖ\u0001J\t\u0010\u0010\u001a\u00020\u0011HÖ\u0001R\u0019\u0010\u0002\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0007\u0010\b¨\u0006\u0013"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/WRRemote$Output;", "", "wr", "", "Lsp/aicoin_kline/core/indicator/config/WRRemote$Output$Wr;", "<init>", "(Ljava/util/List;)V", "getWr", "()Ljava/util/List;", "component1", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Wr", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Output {
        private final List<Wr> wr;

        @Keep
        @Metadata(d1 = {"\u0000\u001e\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\b\n\u0002\b\u0014\b\u0087\b\u0018\u00002\u00020\u0001B+\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0007¢\u0006\u0004\b\b\u0010\tJ\u0010\u0010\u0012\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u000bJ\u000b\u0010\u0013\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010\u0014\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0010J2\u0010\u0015\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0007HÆ\u0001¢\u0006\u0002\u0010\u0016J\u0013\u0010\u0017\u001a\u00020\u00032\b\u0010\u0018\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0019\u001a\u00020\u0007HÖ\u0001J\t\u0010\u001a\u001a\u00020\u0005HÖ\u0001R\u001a\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\f\u001a\u0004\b\n\u0010\u000bR\u0018\u0010\u0004\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\r\u0010\u000eR\u001a\u0010\u0006\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0011\u001a\u0004\b\u000f\u0010\u0010¨\u0006\u001b"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/WRRemote$Output$Wr;", "", "wrDisabled", "", "wrLineColor", "", "wrLineWidth", "", "<init>", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)V", "getWrDisabled", "()Ljava/lang/Boolean;", "Ljava/lang/Boolean;", "getWrLineColor", "()Ljava/lang/String;", "getWrLineWidth", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "component1", "component2", "component3", "copy", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/WRRemote$Output$Wr;", "equals", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
        public static final /* data */ class Wr {

            @SerializedName("wr_disabled")
            private final Boolean wrDisabled;

            @SerializedName("wr_lineColor")
            private final String wrLineColor;

            @SerializedName("wr_lineWidth")
            private final Integer wrLineWidth;

            public Wr() {
                this(null, null, null, 7, null);
            }

            public Wr(Boolean bool, String str, Integer num) {
                this.wrDisabled = bool;
                this.wrLineColor = str;
                this.wrLineWidth = num;
            }

            public /* synthetic */ Wr(Boolean bool, String str, Integer num, int i10, DefaultConstructorMarker defaultConstructorMarker) {
                this((i10 & 1) != 0 ? null : bool, (i10 & 2) != 0 ? null : str, (i10 & 4) != 0 ? null : num);
            }

            public static /* synthetic */ Wr copy$default(Wr wr, Boolean bool, String str, Integer num, int i10, Object obj) {
                if ((i10 & 1) != 0) {
                    bool = wr.wrDisabled;
                }
                if ((i10 & 2) != 0) {
                    str = wr.wrLineColor;
                }
                if ((i10 & 4) != 0) {
                    num = wr.wrLineWidth;
                }
                return wr.copy(bool, str, num);
            }

            /* JADX INFO: renamed from: component1, reason: from getter */
            public final Boolean getWrDisabled() {
                return this.wrDisabled;
            }

            /* JADX INFO: renamed from: component2, reason: from getter */
            public final String getWrLineColor() {
                return this.wrLineColor;
            }

            /* JADX INFO: renamed from: component3, reason: from getter */
            public final Integer getWrLineWidth() {
                return this.wrLineWidth;
            }

            public final Wr copy(Boolean wrDisabled, String wrLineColor, Integer wrLineWidth) {
                return new Wr(wrDisabled, wrLineColor, wrLineWidth);
            }

            public boolean equals(Object other) {
                if (this == other) {
                    return true;
                }
                if (!(other instanceof Wr)) {
                    return false;
                }
                Wr wr = (Wr) other;
                return AbstractC7609s.f(this.wrDisabled, wr.wrDisabled) && AbstractC7609s.f(this.wrLineColor, wr.wrLineColor) && AbstractC7609s.f(this.wrLineWidth, wr.wrLineWidth);
            }

            public final Boolean getWrDisabled() {
                return this.wrDisabled;
            }

            public final String getWrLineColor() {
                return this.wrLineColor;
            }

            public final Integer getWrLineWidth() {
                return this.wrLineWidth;
            }

            public int hashCode() {
                Boolean bool = this.wrDisabled;
                int iHashCode = (bool == null ? 0 : bool.hashCode()) * 31;
                String str = this.wrLineColor;
                int iHashCode2 = (iHashCode + (str == null ? 0 : str.hashCode())) * 31;
                Integer num = this.wrLineWidth;
                return iHashCode2 + (num != null ? num.hashCode() : 0);
            }

            public String toString() {
                StringBuilder sb2 = new StringBuilder("Wr(wrDisabled=");
                sb2.append(this.wrDisabled);
                sb2.append(", wrLineColor=");
                sb2.append(this.wrLineColor);
                sb2.append(", wrLineWidth=");
                return kk.b.a(sb2, this.wrLineWidth, ')');
            }
        }

        public Output(List<Wr> list) {
            this.wr = list;
        }

        /* JADX WARN: Multi-variable type inference failed */
        public static /* synthetic */ Output copy$default(Output output, List list, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                list = output.wr;
            }
            return output.copy(list);
        }

        public final List<Wr> component1() {
            return this.wr;
        }

        public final Output copy(List<Wr> wr) {
            return new Output(wr);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            return (other instanceof Output) && AbstractC7609s.f(this.wr, ((Output) other).wr);
        }

        public final List<Wr> getWr() {
            return this.wr;
        }

        public int hashCode() {
            List<Wr> list = this.wr;
            if (list == null) {
                return 0;
            }
            return list.hashCode();
        }

        public String toString() {
            return "Output(wr=" + this.wr + ')';
        }
    }

    public WRRemote(Input input, Output output, Output output2, Input input2) {
        this.input = input;
        this.output = output;
        this.app_output = output2;
        this.app_input = input2;
    }

    public static /* synthetic */ WRRemote copy$default(WRRemote wRRemote, Input input, Output output, Output output2, Input input2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            input = wRRemote.input;
        }
        if ((i10 & 2) != 0) {
            output = wRRemote.output;
        }
        if ((i10 & 4) != 0) {
            output2 = wRRemote.app_output;
        }
        if ((i10 & 8) != 0) {
            input2 = wRRemote.app_input;
        }
        return wRRemote.copy(input, output, output2, input2);
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

    public final WRRemote copy(Input input, Output output, Output app_output, Input app_input) {
        return new WRRemote(input, output, app_output, app_input);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof WRRemote)) {
            return false;
        }
        WRRemote wRRemote = (WRRemote) other;
        return AbstractC7609s.f(this.input, wRRemote.input) && AbstractC7609s.f(this.output, wRRemote.output) && AbstractC7609s.f(this.app_output, wRRemote.app_output) && AbstractC7609s.f(this.app_input, wRRemote.app_input);
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
        return "WRRemote(input=" + this.input + ", output=" + this.output + ", app_output=" + this.app_output + ", app_input=" + this.app_input + ')';
    }
}
