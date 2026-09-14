package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000.\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0010\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0003\b\u0087\b\u0018\u00002\u00020\u0001:\u0002\u001c\u001dB/\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\b\u0010\tJ\u000b\u0010\u0010\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u0011\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0012\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0013\u001a\u0004\u0018\u00010\u0003HÆ\u0003J9\u0010\u0014\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\u0015\u001a\u00020\u00162\b\u0010\u0017\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0018\u001a\u00020\u0019HÖ\u0001J\t\u0010\u001a\u001a\u00020\u001bHÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\n\u0010\u000bR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\f\u0010\rR\u0013\u0010\u0006\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\rR\u0013\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u000f\u0010\u000b¨\u0006\u001e"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/KDJRemote;", "", "input", "Lsp/aicoin_kline/core/indicator/config/KDJRemote$Input;", "output", "Lsp/aicoin_kline/core/indicator/config/KDJRemote$Output;", "app_output", "app_input", "<init>", "(Lsp/aicoin_kline/core/indicator/config/KDJRemote$Input;Lsp/aicoin_kline/core/indicator/config/KDJRemote$Output;Lsp/aicoin_kline/core/indicator/config/KDJRemote$Output;Lsp/aicoin_kline/core/indicator/config/KDJRemote$Input;)V", "getInput", "()Lsp/aicoin_kline/core/indicator/config/KDJRemote$Input;", "getOutput", "()Lsp/aicoin_kline/core/indicator/config/KDJRemote$Output;", "getApp_output", "getApp_input", "component1", "component2", "component3", "component4", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Input", "Output", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class KDJRemote {
    private final Input app_input;
    private final Output app_output;
    private final Input input;
    private final Output output;

    @Keep
    @Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0002\b\u000f\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0010\u000e\n\u0000\b\u0087\b\u0018\u00002\u00020\u0001B%\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0005\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0006\u0010\u0007J\u0010\u0010\r\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\tJ\u0010\u0010\u000e\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\tJ\u0010\u0010\u000f\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\tJ2\u0010\u0010\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0005\u001a\u0004\u0018\u00010\u0003HÆ\u0001¢\u0006\u0002\u0010\u0011J\u0013\u0010\u0012\u001a\u00020\u00132\b\u0010\u0014\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0015\u001a\u00020\u0003HÖ\u0001J\t\u0010\u0016\u001a\u00020\u0017HÖ\u0001R\u0015\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\n\u001a\u0004\b\b\u0010\tR\u0015\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\n\u001a\u0004\b\u000b\u0010\tR\u0015\u0010\u0005\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\n\u001a\u0004\b\f\u0010\t¨\u0006\u0018"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/KDJRemote$Input;", "", "cc", "", "mac1", "mac2", "<init>", "(Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;)V", "getCc", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getMac1", "getMac2", "component1", "component2", "component3", "copy", "(Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/KDJRemote$Input;", "equals", "", "other", "hashCode", "toString", "", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Input {
        private final Integer cc;
        private final Integer mac1;
        private final Integer mac2;

        public Input(Integer num, Integer num2, Integer num3) {
            this.cc = num;
            this.mac1 = num2;
            this.mac2 = num3;
        }

        public static /* synthetic */ Input copy$default(Input input, Integer num, Integer num2, Integer num3, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                num = input.cc;
            }
            if ((i10 & 2) != 0) {
                num2 = input.mac1;
            }
            if ((i10 & 4) != 0) {
                num3 = input.mac2;
            }
            return input.copy(num, num2, num3);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Integer getCc() {
            return this.cc;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final Integer getMac1() {
            return this.mac1;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final Integer getMac2() {
            return this.mac2;
        }

        public final Input copy(Integer cc2, Integer mac1, Integer mac2) {
            return new Input(cc2, mac1, mac2);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Input)) {
                return false;
            }
            Input input = (Input) other;
            return AbstractC7609s.f(this.cc, input.cc) && AbstractC7609s.f(this.mac1, input.mac1) && AbstractC7609s.f(this.mac2, input.mac2);
        }

        public final Integer getCc() {
            return this.cc;
        }

        public final Integer getMac1() {
            return this.mac1;
        }

        public final Integer getMac2() {
            return this.mac2;
        }

        public int hashCode() {
            Integer num = this.cc;
            int iHashCode = (num == null ? 0 : num.hashCode()) * 31;
            Integer num2 = this.mac1;
            int iHashCode2 = (iHashCode + (num2 == null ? 0 : num2.hashCode())) * 31;
            Integer num3 = this.mac2;
            return iHashCode2 + (num3 != null ? num3.hashCode() : 0);
        }

        public String toString() {
            StringBuilder sb2 = new StringBuilder("Input(cc=");
            sb2.append(this.cc);
            sb2.append(", mac1=");
            sb2.append(this.mac1);
            sb2.append(", mac2=");
            return kk.b.a(sb2, this.mac2, ')');
        }
    }

    @Keep
    @Metadata(d1 = {"\u0000\u001e\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\b\n\u0002\b&\b\u0087\b\u0018\u00002\u00020\u0001Bs\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\u0007¢\u0006\u0004\b\u000e\u0010\u000fJ\u0010\u0010\u001e\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0011J\u000b\u0010\u001f\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010 \u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0016J\u0010\u0010!\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0011J\u000b\u0010\"\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010#\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0016J\u0010\u0010$\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0011J\u000b\u0010%\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010&\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0016Jz\u0010'\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\u0007HÆ\u0001¢\u0006\u0002\u0010(J\u0013\u0010)\u001a\u00020\u00032\b\u0010*\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010+\u001a\u00020\u0007HÖ\u0001J\t\u0010,\u001a\u00020\u0005HÖ\u0001R\u001a\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0012\u001a\u0004\b\u0010\u0010\u0011R\u0018\u0010\u0004\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0013\u0010\u0014R\u001a\u0010\u0006\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0017\u001a\u0004\b\u0015\u0010\u0016R\u001a\u0010\b\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0012\u001a\u0004\b\u0018\u0010\u0011R\u0018\u0010\t\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0019\u0010\u0014R\u001a\u0010\n\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0017\u001a\u0004\b\u001a\u0010\u0016R\u001a\u0010\u000b\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0012\u001a\u0004\b\u001b\u0010\u0011R\u0018\u0010\f\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u001c\u0010\u0014R\u001a\u0010\r\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0017\u001a\u0004\b\u001d\u0010\u0016¨\u0006-"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/KDJRemote$Output;", "", "dDisabled", "", "dLineColor", "", "dLineWidth", "", "jDisabled", "jLineColor", "jLineWidth", "kDisabled", "kLineColor", "kLineWidth", "<init>", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)V", "getDDisabled", "()Ljava/lang/Boolean;", "Ljava/lang/Boolean;", "getDLineColor", "()Ljava/lang/String;", "getDLineWidth", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getJDisabled", "getJLineColor", "getJLineWidth", "getKDisabled", "getKLineColor", "getKLineWidth", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "component9", "copy", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/KDJRemote$Output;", "equals", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Output {

        @SerializedName("d_disabled")
        private final Boolean dDisabled;

        @SerializedName("d_lineColor")
        private final String dLineColor;

        @SerializedName("d_lineWidth")
        private final Integer dLineWidth;

        @SerializedName("j_disabled")
        private final Boolean jDisabled;

        @SerializedName("j_lineColor")
        private final String jLineColor;

        @SerializedName("j_lineWidth")
        private final Integer jLineWidth;

        @SerializedName("k_disabled")
        private final Boolean kDisabled;

        @SerializedName("k_lineColor")
        private final String kLineColor;

        @SerializedName("k_lineWidth")
        private final Integer kLineWidth;

        public Output() {
            this(null, null, null, null, null, null, null, null, null, 511, null);
        }

        public Output(Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2, Boolean bool3, String str3, Integer num3) {
            this.dDisabled = bool;
            this.dLineColor = str;
            this.dLineWidth = num;
            this.jDisabled = bool2;
            this.jLineColor = str2;
            this.jLineWidth = num2;
            this.kDisabled = bool3;
            this.kLineColor = str3;
            this.kLineWidth = num3;
        }

        public /* synthetic */ Output(Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2, Boolean bool3, String str3, Integer num3, int i10, DefaultConstructorMarker defaultConstructorMarker) {
            this((i10 & 1) != 0 ? null : bool, (i10 & 2) != 0 ? null : str, (i10 & 4) != 0 ? null : num, (i10 & 8) != 0 ? null : bool2, (i10 & 16) != 0 ? null : str2, (i10 & 32) != 0 ? null : num2, (i10 & 64) != 0 ? null : bool3, (i10 & 128) != 0 ? null : str3, (i10 & 256) != 0 ? null : num3);
        }

        public static /* synthetic */ Output copy$default(Output output, Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2, Boolean bool3, String str3, Integer num3, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                bool = output.dDisabled;
            }
            if ((i10 & 2) != 0) {
                str = output.dLineColor;
            }
            if ((i10 & 4) != 0) {
                num = output.dLineWidth;
            }
            if ((i10 & 8) != 0) {
                bool2 = output.jDisabled;
            }
            if ((i10 & 16) != 0) {
                str2 = output.jLineColor;
            }
            if ((i10 & 32) != 0) {
                num2 = output.jLineWidth;
            }
            if ((i10 & 64) != 0) {
                bool3 = output.kDisabled;
            }
            if ((i10 & 128) != 0) {
                str3 = output.kLineColor;
            }
            if ((i10 & 256) != 0) {
                num3 = output.kLineWidth;
            }
            String str4 = str3;
            Integer num4 = num3;
            Integer num5 = num2;
            Boolean bool4 = bool3;
            String str5 = str2;
            Integer num6 = num;
            return output.copy(bool, str, num6, bool2, str5, num5, bool4, str4, num4);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Boolean getDDisabled() {
            return this.dDisabled;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final String getDLineColor() {
            return this.dLineColor;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final Integer getDLineWidth() {
            return this.dLineWidth;
        }

        /* JADX INFO: renamed from: component4, reason: from getter */
        public final Boolean getJDisabled() {
            return this.jDisabled;
        }

        /* JADX INFO: renamed from: component5, reason: from getter */
        public final String getJLineColor() {
            return this.jLineColor;
        }

        /* JADX INFO: renamed from: component6, reason: from getter */
        public final Integer getJLineWidth() {
            return this.jLineWidth;
        }

        /* JADX INFO: renamed from: component7, reason: from getter */
        public final Boolean getKDisabled() {
            return this.kDisabled;
        }

        /* JADX INFO: renamed from: component8, reason: from getter */
        public final String getKLineColor() {
            return this.kLineColor;
        }

        /* JADX INFO: renamed from: component9, reason: from getter */
        public final Integer getKLineWidth() {
            return this.kLineWidth;
        }

        public final Output copy(Boolean dDisabled, String dLineColor, Integer dLineWidth, Boolean jDisabled, String jLineColor, Integer jLineWidth, Boolean kDisabled, String kLineColor, Integer kLineWidth) {
            return new Output(dDisabled, dLineColor, dLineWidth, jDisabled, jLineColor, jLineWidth, kDisabled, kLineColor, kLineWidth);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Output)) {
                return false;
            }
            Output output = (Output) other;
            return AbstractC7609s.f(this.dDisabled, output.dDisabled) && AbstractC7609s.f(this.dLineColor, output.dLineColor) && AbstractC7609s.f(this.dLineWidth, output.dLineWidth) && AbstractC7609s.f(this.jDisabled, output.jDisabled) && AbstractC7609s.f(this.jLineColor, output.jLineColor) && AbstractC7609s.f(this.jLineWidth, output.jLineWidth) && AbstractC7609s.f(this.kDisabled, output.kDisabled) && AbstractC7609s.f(this.kLineColor, output.kLineColor) && AbstractC7609s.f(this.kLineWidth, output.kLineWidth);
        }

        public final Boolean getDDisabled() {
            return this.dDisabled;
        }

        public final String getDLineColor() {
            return this.dLineColor;
        }

        public final Integer getDLineWidth() {
            return this.dLineWidth;
        }

        public final Boolean getJDisabled() {
            return this.jDisabled;
        }

        public final String getJLineColor() {
            return this.jLineColor;
        }

        public final Integer getJLineWidth() {
            return this.jLineWidth;
        }

        public final Boolean getKDisabled() {
            return this.kDisabled;
        }

        public final String getKLineColor() {
            return this.kLineColor;
        }

        public final Integer getKLineWidth() {
            return this.kLineWidth;
        }

        public int hashCode() {
            Boolean bool = this.dDisabled;
            int iHashCode = (bool == null ? 0 : bool.hashCode()) * 31;
            String str = this.dLineColor;
            int iHashCode2 = (iHashCode + (str == null ? 0 : str.hashCode())) * 31;
            Integer num = this.dLineWidth;
            int iHashCode3 = (iHashCode2 + (num == null ? 0 : num.hashCode())) * 31;
            Boolean bool2 = this.jDisabled;
            int iHashCode4 = (iHashCode3 + (bool2 == null ? 0 : bool2.hashCode())) * 31;
            String str2 = this.jLineColor;
            int iHashCode5 = (iHashCode4 + (str2 == null ? 0 : str2.hashCode())) * 31;
            Integer num2 = this.jLineWidth;
            int iHashCode6 = (iHashCode5 + (num2 == null ? 0 : num2.hashCode())) * 31;
            Boolean bool3 = this.kDisabled;
            int iHashCode7 = (iHashCode6 + (bool3 == null ? 0 : bool3.hashCode())) * 31;
            String str3 = this.kLineColor;
            int iHashCode8 = (iHashCode7 + (str3 == null ? 0 : str3.hashCode())) * 31;
            Integer num3 = this.kLineWidth;
            return iHashCode8 + (num3 != null ? num3.hashCode() : 0);
        }

        public String toString() {
            StringBuilder sb2 = new StringBuilder("Output(dDisabled=");
            sb2.append(this.dDisabled);
            sb2.append(", dLineColor=");
            sb2.append(this.dLineColor);
            sb2.append(", dLineWidth=");
            sb2.append(this.dLineWidth);
            sb2.append(", jDisabled=");
            sb2.append(this.jDisabled);
            sb2.append(", jLineColor=");
            sb2.append(this.jLineColor);
            sb2.append(", jLineWidth=");
            sb2.append(this.jLineWidth);
            sb2.append(", kDisabled=");
            sb2.append(this.kDisabled);
            sb2.append(", kLineColor=");
            sb2.append(this.kLineColor);
            sb2.append(", kLineWidth=");
            return kk.b.a(sb2, this.kLineWidth, ')');
        }
    }

    public KDJRemote(Input input, Output output, Output output2, Input input2) {
        this.input = input;
        this.output = output;
        this.app_output = output2;
        this.app_input = input2;
    }

    public static /* synthetic */ KDJRemote copy$default(KDJRemote kDJRemote, Input input, Output output, Output output2, Input input2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            input = kDJRemote.input;
        }
        if ((i10 & 2) != 0) {
            output = kDJRemote.output;
        }
        if ((i10 & 4) != 0) {
            output2 = kDJRemote.app_output;
        }
        if ((i10 & 8) != 0) {
            input2 = kDJRemote.app_input;
        }
        return kDJRemote.copy(input, output, output2, input2);
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

    public final KDJRemote copy(Input input, Output output, Output app_output, Input app_input) {
        return new KDJRemote(input, output, app_output, app_input);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof KDJRemote)) {
            return false;
        }
        KDJRemote kDJRemote = (KDJRemote) other;
        return AbstractC7609s.f(this.input, kDJRemote.input) && AbstractC7609s.f(this.output, kDJRemote.output) && AbstractC7609s.f(this.app_output, kDJRemote.app_output) && AbstractC7609s.f(this.app_input, kDJRemote.app_input);
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
        return "KDJRemote(input=" + this.input + ", output=" + this.output + ", app_output=" + this.app_output + ", app_input=" + this.app_input + ')';
    }
}
