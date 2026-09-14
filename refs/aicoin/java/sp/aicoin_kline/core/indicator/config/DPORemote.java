package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000.\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0010\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0003\b\u0087\b\u0018\u00002\u00020\u0001:\u0002\u001c\u001dB/\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\b\u0010\tJ\u000b\u0010\u0010\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u0011\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0012\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0013\u001a\u0004\u0018\u00010\u0003HÆ\u0003J9\u0010\u0014\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\u0015\u001a\u00020\u00162\b\u0010\u0017\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0018\u001a\u00020\u0019HÖ\u0001J\t\u0010\u001a\u001a\u00020\u001bHÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\n\u0010\u000bR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\f\u0010\rR\u0013\u0010\u0006\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\rR\u0013\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u000f\u0010\u000b¨\u0006\u001e"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/DPORemote;", "", "input", "Lsp/aicoin_kline/core/indicator/config/DPORemote$Input;", "output", "Lsp/aicoin_kline/core/indicator/config/DPORemote$Output;", "app_output", "app_input", "<init>", "(Lsp/aicoin_kline/core/indicator/config/DPORemote$Input;Lsp/aicoin_kline/core/indicator/config/DPORemote$Output;Lsp/aicoin_kline/core/indicator/config/DPORemote$Output;Lsp/aicoin_kline/core/indicator/config/DPORemote$Input;)V", "getInput", "()Lsp/aicoin_kline/core/indicator/config/DPORemote$Input;", "getOutput", "()Lsp/aicoin_kline/core/indicator/config/DPORemote$Output;", "getApp_output", "getApp_input", "component1", "component2", "component3", "component4", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Input", "Output", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class DPORemote {
    private final Input app_input;
    private final Output app_output;
    private final Input input;
    private final Output output;

    @Keep
    @Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0002\b\f\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0010\u000e\n\u0000\b\u0087\b\u0018\u00002\u00020\u0001B\u001b\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0005\u0010\u0006J\u0010\u0010\u000b\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\bJ\u0010\u0010\f\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\bJ&\u0010\r\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0003HÆ\u0001¢\u0006\u0002\u0010\u000eJ\u0013\u0010\u000f\u001a\u00020\u00102\b\u0010\u0011\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0012\u001a\u00020\u0003HÖ\u0001J\t\u0010\u0013\u001a\u00020\u0014HÖ\u0001R\u0015\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\t\u001a\u0004\b\u0007\u0010\bR\u0015\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\t\u001a\u0004\b\n\u0010\b¨\u0006\u0015"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/DPORemote$Input;", "", "cc", "", "mac", "<init>", "(Ljava/lang/Integer;Ljava/lang/Integer;)V", "getCc", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getMac", "component1", "component2", "copy", "(Ljava/lang/Integer;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/DPORemote$Input;", "equals", "", "other", "hashCode", "toString", "", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
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
    @Metadata(d1 = {"\u0000\u001e\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\b\n\u0002\b&\b\u0087\b\u0018\u00002\u00020\u0001Bs\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\u0007¢\u0006\u0004\b\u000e\u0010\u000fJ\u0010\u0010\u001e\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0011J\u000b\u0010\u001f\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010 \u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0016J\u0010\u0010!\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0011J\u000b\u0010\"\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010#\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0016J\u0010\u0010$\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0011J\u000b\u0010%\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010&\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0016Jz\u0010'\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\u0007HÆ\u0001¢\u0006\u0002\u0010(J\u0013\u0010)\u001a\u00020\u00032\b\u0010*\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010+\u001a\u00020\u0007HÖ\u0001J\t\u0010,\u001a\u00020\u0005HÖ\u0001R\u001a\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0012\u001a\u0004\b\u0010\u0010\u0011R\u0018\u0010\u0004\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0013\u0010\u0014R\u001a\u0010\u0006\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0017\u001a\u0004\b\u0015\u0010\u0016R\u001a\u0010\b\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0012\u001a\u0004\b\u0018\u0010\u0011R\u0018\u0010\t\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0019\u0010\u0014R\u001a\u0010\n\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0017\u001a\u0004\b\u001a\u0010\u0016R\u001a\u0010\u000b\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0012\u001a\u0004\b\u001b\u0010\u0011R\u0018\u0010\f\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u001c\u0010\u0014R\u001a\u0010\r\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0017\u001a\u0004\b\u001d\u0010\u0016¨\u0006-"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/DPORemote$Output;", "", "dpoDisabled", "", "dpoLineColor", "", "dpoLineWidth", "", "maDpoDisabled", "maDpoLineColor", "maDpoLineWidth", "zeroBandDisabled", "zeroBandLineColor", "zeroBandLineWidth", "<init>", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)V", "getDpoDisabled", "()Ljava/lang/Boolean;", "Ljava/lang/Boolean;", "getDpoLineColor", "()Ljava/lang/String;", "getDpoLineWidth", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getMaDpoDisabled", "getMaDpoLineColor", "getMaDpoLineWidth", "getZeroBandDisabled", "getZeroBandLineColor", "getZeroBandLineWidth", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "component9", "copy", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/DPORemote$Output;", "equals", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Output {

        @SerializedName("dpo_disabled")
        private final Boolean dpoDisabled;

        @SerializedName("dpo_lineColor")
        private final String dpoLineColor;

        @SerializedName("dpo_lineWidth")
        private final Integer dpoLineWidth;

        @SerializedName("maDpo_disabled")
        private final Boolean maDpoDisabled;

        @SerializedName("maDpo_lineColor")
        private final String maDpoLineColor;

        @SerializedName("maDpo_lineWidth")
        private final Integer maDpoLineWidth;

        @SerializedName("zeroBand_disabled")
        private final Boolean zeroBandDisabled;

        @SerializedName("zeroBand_lineColor")
        private final String zeroBandLineColor;

        @SerializedName("zeroBand_lineWidth")
        private final Integer zeroBandLineWidth;

        public Output() {
            this(null, null, null, null, null, null, null, null, null, 511, null);
        }

        public Output(Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2, Boolean bool3, String str3, Integer num3) {
            this.dpoDisabled = bool;
            this.dpoLineColor = str;
            this.dpoLineWidth = num;
            this.maDpoDisabled = bool2;
            this.maDpoLineColor = str2;
            this.maDpoLineWidth = num2;
            this.zeroBandDisabled = bool3;
            this.zeroBandLineColor = str3;
            this.zeroBandLineWidth = num3;
        }

        public /* synthetic */ Output(Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2, Boolean bool3, String str3, Integer num3, int i10, DefaultConstructorMarker defaultConstructorMarker) {
            this((i10 & 1) != 0 ? null : bool, (i10 & 2) != 0 ? null : str, (i10 & 4) != 0 ? null : num, (i10 & 8) != 0 ? null : bool2, (i10 & 16) != 0 ? null : str2, (i10 & 32) != 0 ? null : num2, (i10 & 64) != 0 ? null : bool3, (i10 & 128) != 0 ? null : str3, (i10 & 256) != 0 ? null : num3);
        }

        public static /* synthetic */ Output copy$default(Output output, Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2, Boolean bool3, String str3, Integer num3, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                bool = output.dpoDisabled;
            }
            if ((i10 & 2) != 0) {
                str = output.dpoLineColor;
            }
            if ((i10 & 4) != 0) {
                num = output.dpoLineWidth;
            }
            if ((i10 & 8) != 0) {
                bool2 = output.maDpoDisabled;
            }
            if ((i10 & 16) != 0) {
                str2 = output.maDpoLineColor;
            }
            if ((i10 & 32) != 0) {
                num2 = output.maDpoLineWidth;
            }
            if ((i10 & 64) != 0) {
                bool3 = output.zeroBandDisabled;
            }
            if ((i10 & 128) != 0) {
                str3 = output.zeroBandLineColor;
            }
            if ((i10 & 256) != 0) {
                num3 = output.zeroBandLineWidth;
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
        public final Boolean getDpoDisabled() {
            return this.dpoDisabled;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final String getDpoLineColor() {
            return this.dpoLineColor;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final Integer getDpoLineWidth() {
            return this.dpoLineWidth;
        }

        /* JADX INFO: renamed from: component4, reason: from getter */
        public final Boolean getMaDpoDisabled() {
            return this.maDpoDisabled;
        }

        /* JADX INFO: renamed from: component5, reason: from getter */
        public final String getMaDpoLineColor() {
            return this.maDpoLineColor;
        }

        /* JADX INFO: renamed from: component6, reason: from getter */
        public final Integer getMaDpoLineWidth() {
            return this.maDpoLineWidth;
        }

        /* JADX INFO: renamed from: component7, reason: from getter */
        public final Boolean getZeroBandDisabled() {
            return this.zeroBandDisabled;
        }

        /* JADX INFO: renamed from: component8, reason: from getter */
        public final String getZeroBandLineColor() {
            return this.zeroBandLineColor;
        }

        /* JADX INFO: renamed from: component9, reason: from getter */
        public final Integer getZeroBandLineWidth() {
            return this.zeroBandLineWidth;
        }

        public final Output copy(Boolean dpoDisabled, String dpoLineColor, Integer dpoLineWidth, Boolean maDpoDisabled, String maDpoLineColor, Integer maDpoLineWidth, Boolean zeroBandDisabled, String zeroBandLineColor, Integer zeroBandLineWidth) {
            return new Output(dpoDisabled, dpoLineColor, dpoLineWidth, maDpoDisabled, maDpoLineColor, maDpoLineWidth, zeroBandDisabled, zeroBandLineColor, zeroBandLineWidth);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Output)) {
                return false;
            }
            Output output = (Output) other;
            return AbstractC7609s.f(this.dpoDisabled, output.dpoDisabled) && AbstractC7609s.f(this.dpoLineColor, output.dpoLineColor) && AbstractC7609s.f(this.dpoLineWidth, output.dpoLineWidth) && AbstractC7609s.f(this.maDpoDisabled, output.maDpoDisabled) && AbstractC7609s.f(this.maDpoLineColor, output.maDpoLineColor) && AbstractC7609s.f(this.maDpoLineWidth, output.maDpoLineWidth) && AbstractC7609s.f(this.zeroBandDisabled, output.zeroBandDisabled) && AbstractC7609s.f(this.zeroBandLineColor, output.zeroBandLineColor) && AbstractC7609s.f(this.zeroBandLineWidth, output.zeroBandLineWidth);
        }

        public final Boolean getDpoDisabled() {
            return this.dpoDisabled;
        }

        public final String getDpoLineColor() {
            return this.dpoLineColor;
        }

        public final Integer getDpoLineWidth() {
            return this.dpoLineWidth;
        }

        public final Boolean getMaDpoDisabled() {
            return this.maDpoDisabled;
        }

        public final String getMaDpoLineColor() {
            return this.maDpoLineColor;
        }

        public final Integer getMaDpoLineWidth() {
            return this.maDpoLineWidth;
        }

        public final Boolean getZeroBandDisabled() {
            return this.zeroBandDisabled;
        }

        public final String getZeroBandLineColor() {
            return this.zeroBandLineColor;
        }

        public final Integer getZeroBandLineWidth() {
            return this.zeroBandLineWidth;
        }

        public int hashCode() {
            Boolean bool = this.dpoDisabled;
            int iHashCode = (bool == null ? 0 : bool.hashCode()) * 31;
            String str = this.dpoLineColor;
            int iHashCode2 = (iHashCode + (str == null ? 0 : str.hashCode())) * 31;
            Integer num = this.dpoLineWidth;
            int iHashCode3 = (iHashCode2 + (num == null ? 0 : num.hashCode())) * 31;
            Boolean bool2 = this.maDpoDisabled;
            int iHashCode4 = (iHashCode3 + (bool2 == null ? 0 : bool2.hashCode())) * 31;
            String str2 = this.maDpoLineColor;
            int iHashCode5 = (iHashCode4 + (str2 == null ? 0 : str2.hashCode())) * 31;
            Integer num2 = this.maDpoLineWidth;
            int iHashCode6 = (iHashCode5 + (num2 == null ? 0 : num2.hashCode())) * 31;
            Boolean bool3 = this.zeroBandDisabled;
            int iHashCode7 = (iHashCode6 + (bool3 == null ? 0 : bool3.hashCode())) * 31;
            String str3 = this.zeroBandLineColor;
            int iHashCode8 = (iHashCode7 + (str3 == null ? 0 : str3.hashCode())) * 31;
            Integer num3 = this.zeroBandLineWidth;
            return iHashCode8 + (num3 != null ? num3.hashCode() : 0);
        }

        public String toString() {
            StringBuilder sb2 = new StringBuilder("Output(dpoDisabled=");
            sb2.append(this.dpoDisabled);
            sb2.append(", dpoLineColor=");
            sb2.append(this.dpoLineColor);
            sb2.append(", dpoLineWidth=");
            sb2.append(this.dpoLineWidth);
            sb2.append(", maDpoDisabled=");
            sb2.append(this.maDpoDisabled);
            sb2.append(", maDpoLineColor=");
            sb2.append(this.maDpoLineColor);
            sb2.append(", maDpoLineWidth=");
            sb2.append(this.maDpoLineWidth);
            sb2.append(", zeroBandDisabled=");
            sb2.append(this.zeroBandDisabled);
            sb2.append(", zeroBandLineColor=");
            sb2.append(this.zeroBandLineColor);
            sb2.append(", zeroBandLineWidth=");
            return kk.b.a(sb2, this.zeroBandLineWidth, ')');
        }
    }

    public DPORemote(Input input, Output output, Output output2, Input input2) {
        this.input = input;
        this.output = output;
        this.app_output = output2;
        this.app_input = input2;
    }

    public static /* synthetic */ DPORemote copy$default(DPORemote dPORemote, Input input, Output output, Output output2, Input input2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            input = dPORemote.input;
        }
        if ((i10 & 2) != 0) {
            output = dPORemote.output;
        }
        if ((i10 & 4) != 0) {
            output2 = dPORemote.app_output;
        }
        if ((i10 & 8) != 0) {
            input2 = dPORemote.app_input;
        }
        return dPORemote.copy(input, output, output2, input2);
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

    public final DPORemote copy(Input input, Output output, Output app_output, Input app_input) {
        return new DPORemote(input, output, app_output, app_input);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof DPORemote)) {
            return false;
        }
        DPORemote dPORemote = (DPORemote) other;
        return AbstractC7609s.f(this.input, dPORemote.input) && AbstractC7609s.f(this.output, dPORemote.output) && AbstractC7609s.f(this.app_output, dPORemote.app_output) && AbstractC7609s.f(this.app_input, dPORemote.app_input);
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
        return "DPORemote(input=" + this.input + ", output=" + this.output + ", app_output=" + this.app_output + ", app_input=" + this.app_input + ')';
    }
}
