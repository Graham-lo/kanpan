package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000.\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0010\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0003\b\u0087\b\u0018\u00002\u00020\u0001:\u0002\u001c\u001dB/\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\b\u0010\tJ\u000b\u0010\u0010\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u0011\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0012\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0013\u001a\u0004\u0018\u00010\u0003HÆ\u0003J9\u0010\u0014\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\u0015\u001a\u00020\u00162\b\u0010\u0017\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0018\u001a\u00020\u0019HÖ\u0001J\t\u0010\u001a\u001a\u00020\u001bHÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\n\u0010\u000bR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\f\u0010\rR\u0013\u0010\u0006\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\rR\u0013\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u000f\u0010\u000b¨\u0006\u001e"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/StochRSIRemote;", "", "input", "Lsp/aicoin_kline/core/indicator/config/StochRSIRemote$Input;", "output", "Lsp/aicoin_kline/core/indicator/config/StochRSIRemote$Output;", "app_output", "app_input", "<init>", "(Lsp/aicoin_kline/core/indicator/config/StochRSIRemote$Input;Lsp/aicoin_kline/core/indicator/config/StochRSIRemote$Output;Lsp/aicoin_kline/core/indicator/config/StochRSIRemote$Output;Lsp/aicoin_kline/core/indicator/config/StochRSIRemote$Input;)V", "getInput", "()Lsp/aicoin_kline/core/indicator/config/StochRSIRemote$Input;", "getOutput", "()Lsp/aicoin_kline/core/indicator/config/StochRSIRemote$Output;", "getApp_output", "getApp_input", "component1", "component2", "component3", "component4", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Input", "Output", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class StochRSIRemote {
    private final Input app_input;
    private final Output app_output;
    private final Input input;
    private final Output output;

    @Keep
    @Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0002\b\u0018\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0010\u000e\n\u0000\b\u0087\b\u0018\u00002\u00020\u0001BC\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0005\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0006\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0007\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\b\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\t\u0010\nJ\u0010\u0010\u0013\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\fJ\u0010\u0010\u0014\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\fJ\u0010\u0010\u0015\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\fJ\u0010\u0010\u0016\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\fJ\u0010\u0010\u0017\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\fJ\u0010\u0010\u0018\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\fJV\u0010\u0019\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0005\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u0003HÆ\u0001¢\u0006\u0002\u0010\u001aJ\u0013\u0010\u001b\u001a\u00020\u001c2\b\u0010\u001d\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u001e\u001a\u00020\u0003HÖ\u0001J\t\u0010\u001f\u001a\u00020 HÖ\u0001R\u0015\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\r\u001a\u0004\b\u000b\u0010\fR\u0015\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\r\u001a\u0004\b\u000e\u0010\fR\u0015\u0010\u0005\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\r\u001a\u0004\b\u000f\u0010\fR\u0015\u0010\u0006\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\r\u001a\u0004\b\u0010\u0010\fR\u0015\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\r\u001a\u0004\b\u0011\u0010\fR\u0015\u0010\b\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\r\u001a\u0004\b\u0012\u0010\f¨\u0006!"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/StochRSIRemote$Input;", "", "d", "", "k", "lowerBand", "rsiLength", "stochLength", "upperBand", "<init>", "(Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;)V", "getD", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getK", "getLowerBand", "getRsiLength", "getStochLength", "getUpperBand", "component1", "component2", "component3", "component4", "component5", "component6", "copy", "(Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/StochRSIRemote$Input;", "equals", "", "other", "hashCode", "toString", "", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Input {
        private final Integer d;
        private final Integer k;
        private final Integer lowerBand;
        private final Integer rsiLength;
        private final Integer stochLength;
        private final Integer upperBand;

        public Input(Integer num, Integer num2, Integer num3, Integer num4, Integer num5, Integer num6) {
            this.d = num;
            this.k = num2;
            this.lowerBand = num3;
            this.rsiLength = num4;
            this.stochLength = num5;
            this.upperBand = num6;
        }

        public static /* synthetic */ Input copy$default(Input input, Integer num, Integer num2, Integer num3, Integer num4, Integer num5, Integer num6, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                num = input.d;
            }
            if ((i10 & 2) != 0) {
                num2 = input.k;
            }
            if ((i10 & 4) != 0) {
                num3 = input.lowerBand;
            }
            if ((i10 & 8) != 0) {
                num4 = input.rsiLength;
            }
            if ((i10 & 16) != 0) {
                num5 = input.stochLength;
            }
            if ((i10 & 32) != 0) {
                num6 = input.upperBand;
            }
            Integer num7 = num5;
            Integer num8 = num6;
            return input.copy(num, num2, num3, num4, num7, num8);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Integer getD() {
            return this.d;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final Integer getK() {
            return this.k;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final Integer getLowerBand() {
            return this.lowerBand;
        }

        /* JADX INFO: renamed from: component4, reason: from getter */
        public final Integer getRsiLength() {
            return this.rsiLength;
        }

        /* JADX INFO: renamed from: component5, reason: from getter */
        public final Integer getStochLength() {
            return this.stochLength;
        }

        /* JADX INFO: renamed from: component6, reason: from getter */
        public final Integer getUpperBand() {
            return this.upperBand;
        }

        public final Input copy(Integer d10, Integer k10, Integer lowerBand, Integer rsiLength, Integer stochLength, Integer upperBand) {
            return new Input(d10, k10, lowerBand, rsiLength, stochLength, upperBand);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Input)) {
                return false;
            }
            Input input = (Input) other;
            return AbstractC7609s.f(this.d, input.d) && AbstractC7609s.f(this.k, input.k) && AbstractC7609s.f(this.lowerBand, input.lowerBand) && AbstractC7609s.f(this.rsiLength, input.rsiLength) && AbstractC7609s.f(this.stochLength, input.stochLength) && AbstractC7609s.f(this.upperBand, input.upperBand);
        }

        public final Integer getD() {
            return this.d;
        }

        public final Integer getK() {
            return this.k;
        }

        public final Integer getLowerBand() {
            return this.lowerBand;
        }

        public final Integer getRsiLength() {
            return this.rsiLength;
        }

        public final Integer getStochLength() {
            return this.stochLength;
        }

        public final Integer getUpperBand() {
            return this.upperBand;
        }

        public int hashCode() {
            Integer num = this.d;
            int iHashCode = (num == null ? 0 : num.hashCode()) * 31;
            Integer num2 = this.k;
            int iHashCode2 = (iHashCode + (num2 == null ? 0 : num2.hashCode())) * 31;
            Integer num3 = this.lowerBand;
            int iHashCode3 = (iHashCode2 + (num3 == null ? 0 : num3.hashCode())) * 31;
            Integer num4 = this.rsiLength;
            int iHashCode4 = (iHashCode3 + (num4 == null ? 0 : num4.hashCode())) * 31;
            Integer num5 = this.stochLength;
            int iHashCode5 = (iHashCode4 + (num5 == null ? 0 : num5.hashCode())) * 31;
            Integer num6 = this.upperBand;
            return iHashCode5 + (num6 != null ? num6.hashCode() : 0);
        }

        public String toString() {
            StringBuilder sb2 = new StringBuilder("Input(d=");
            sb2.append(this.d);
            sb2.append(", k=");
            sb2.append(this.k);
            sb2.append(", lowerBand=");
            sb2.append(this.lowerBand);
            sb2.append(", rsiLength=");
            sb2.append(this.rsiLength);
            sb2.append(", stochLength=");
            sb2.append(this.stochLength);
            sb2.append(", upperBand=");
            return kk.b.a(sb2, this.upperBand, ')');
        }
    }

    @Keep
    @Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0010\b\n\u0002\b3\b\u0087\b\u0018\u00002\u00020\u0001B¯\u0001\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\t\u0012\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\t\u0012\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u000e\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u000f\u001a\u0004\u0018\u00010\t\u0012\n\b\u0002\u0010\u0010\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0011\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0012\u001a\u0004\u0018\u00010\t¢\u0006\u0004\b\u0013\u0010\u0014J\u000b\u0010(\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0010\u0010)\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u0018J\u0010\u0010*\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u0018J\u000b\u0010+\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0010\u0010,\u001a\u0004\u0018\u00010\tHÆ\u0003¢\u0006\u0002\u0010\u001dJ\u0010\u0010-\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u0018J\u000b\u0010.\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0010\u0010/\u001a\u0004\u0018\u00010\tHÆ\u0003¢\u0006\u0002\u0010\u001dJ\u0010\u00100\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u0018J\u000b\u00101\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0010\u00102\u001a\u0004\u0018\u00010\tHÆ\u0003¢\u0006\u0002\u0010\u001dJ\u0010\u00103\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u0018J\u000b\u00104\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0010\u00105\u001a\u0004\u0018\u00010\tHÆ\u0003¢\u0006\u0002\u0010\u001dJ¶\u0001\u00106\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\t2\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\t2\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u000e\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u000f\u001a\u0004\u0018\u00010\t2\n\b\u0002\u0010\u0010\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0011\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0012\u001a\u0004\u0018\u00010\tHÆ\u0001¢\u0006\u0002\u00107J\u0013\u00108\u001a\u00020\u00052\b\u00109\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010:\u001a\u00020\tHÖ\u0001J\t\u0010;\u001a\u00020\u0003HÖ\u0001R\u0018\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0015\u0010\u0016R\u001a\u0010\u0004\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0019\u001a\u0004\b\u0017\u0010\u0018R\u001a\u0010\u0006\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0019\u001a\u0004\b\u001a\u0010\u0018R\u0018\u0010\u0007\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u001b\u0010\u0016R\u001a\u0010\b\u001a\u0004\u0018\u00010\t8\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u001e\u001a\u0004\b\u001c\u0010\u001dR\u001a\u0010\n\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0019\u001a\u0004\b\u001f\u0010\u0018R\u0018\u0010\u000b\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b \u0010\u0016R\u001a\u0010\f\u001a\u0004\u0018\u00010\t8\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u001e\u001a\u0004\b!\u0010\u001dR\u001a\u0010\r\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0019\u001a\u0004\b\"\u0010\u0018R\u0018\u0010\u000e\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b#\u0010\u0016R\u001a\u0010\u000f\u001a\u0004\u0018\u00010\t8\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u001e\u001a\u0004\b$\u0010\u001dR\u001a\u0010\u0010\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0019\u001a\u0004\b%\u0010\u0018R\u0018\u0010\u0011\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b&\u0010\u0016R\u001a\u0010\u0012\u001a\u0004\u0018\u00010\t8\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u001e\u001a\u0004\b'\u0010\u001d¨\u0006<"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/StochRSIRemote$Output;", "", "bandAreaBackground", "", "bandAreaDisabled", "", "lowerBandDisabled", "lowerBandLineColor", "lowerBandLineWidth", "", "maStochRsiDisabled", "maStochRsiLineColor", "maStochRsiLineWidth", "stochRsiDisabled", "stochRsiLineColor", "stochRsiLineWidth", "upperBandDisabled", "upperBandLineColor", "upperBandLineWidth", "<init>", "(Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)V", "getBandAreaBackground", "()Ljava/lang/String;", "getBandAreaDisabled", "()Ljava/lang/Boolean;", "Ljava/lang/Boolean;", "getLowerBandDisabled", "getLowerBandLineColor", "getLowerBandLineWidth", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getMaStochRsiDisabled", "getMaStochRsiLineColor", "getMaStochRsiLineWidth", "getStochRsiDisabled", "getStochRsiLineColor", "getStochRsiLineWidth", "getUpperBandDisabled", "getUpperBandLineColor", "getUpperBandLineWidth", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "component9", "component10", "component11", "component12", "component13", "component14", "copy", "(Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/StochRSIRemote$Output;", "equals", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Output {

        @SerializedName("bandArea_background")
        private final String bandAreaBackground;

        @SerializedName("bandArea_disabled")
        private final Boolean bandAreaDisabled;

        @SerializedName("lowerBand_disabled")
        private final Boolean lowerBandDisabled;

        @SerializedName("lowerBand_lineColor")
        private final String lowerBandLineColor;

        @SerializedName("lowerBand_lineWidth")
        private final Integer lowerBandLineWidth;

        @SerializedName("maStochRsi_disabled")
        private final Boolean maStochRsiDisabled;

        @SerializedName("maStochRsi_lineColor")
        private final String maStochRsiLineColor;

        @SerializedName("maStochRsi_lineWidth")
        private final Integer maStochRsiLineWidth;

        @SerializedName("stochRsi_disabled")
        private final Boolean stochRsiDisabled;

        @SerializedName("stochRsi_lineColor")
        private final String stochRsiLineColor;

        @SerializedName("stochRsi_lineWidth")
        private final Integer stochRsiLineWidth;

        @SerializedName("upperBand_disabled")
        private final Boolean upperBandDisabled;

        @SerializedName("upperBand_lineColor")
        private final String upperBandLineColor;

        @SerializedName("upperBand_lineWidth")
        private final Integer upperBandLineWidth;

        public Output() {
            this(null, null, null, null, null, null, null, null, null, null, null, null, null, null, 16383, null);
        }

        public Output(String str, Boolean bool, Boolean bool2, String str2, Integer num, Boolean bool3, String str3, Integer num2, Boolean bool4, String str4, Integer num3, Boolean bool5, String str5, Integer num4) {
            this.bandAreaBackground = str;
            this.bandAreaDisabled = bool;
            this.lowerBandDisabled = bool2;
            this.lowerBandLineColor = str2;
            this.lowerBandLineWidth = num;
            this.maStochRsiDisabled = bool3;
            this.maStochRsiLineColor = str3;
            this.maStochRsiLineWidth = num2;
            this.stochRsiDisabled = bool4;
            this.stochRsiLineColor = str4;
            this.stochRsiLineWidth = num3;
            this.upperBandDisabled = bool5;
            this.upperBandLineColor = str5;
            this.upperBandLineWidth = num4;
        }

        public /* synthetic */ Output(String str, Boolean bool, Boolean bool2, String str2, Integer num, Boolean bool3, String str3, Integer num2, Boolean bool4, String str4, Integer num3, Boolean bool5, String str5, Integer num4, int i10, DefaultConstructorMarker defaultConstructorMarker) {
            this((i10 & 1) != 0 ? null : str, (i10 & 2) != 0 ? null : bool, (i10 & 4) != 0 ? null : bool2, (i10 & 8) != 0 ? null : str2, (i10 & 16) != 0 ? null : num, (i10 & 32) != 0 ? null : bool3, (i10 & 64) != 0 ? null : str3, (i10 & 128) != 0 ? null : num2, (i10 & 256) != 0 ? null : bool4, (i10 & 512) != 0 ? null : str4, (i10 & 1024) != 0 ? null : num3, (i10 & 2048) != 0 ? null : bool5, (i10 & 4096) != 0 ? null : str5, (i10 & 8192) != 0 ? null : num4);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final String getBandAreaBackground() {
            return this.bandAreaBackground;
        }

        /* JADX INFO: renamed from: component10, reason: from getter */
        public final String getStochRsiLineColor() {
            return this.stochRsiLineColor;
        }

        /* JADX INFO: renamed from: component11, reason: from getter */
        public final Integer getStochRsiLineWidth() {
            return this.stochRsiLineWidth;
        }

        /* JADX INFO: renamed from: component12, reason: from getter */
        public final Boolean getUpperBandDisabled() {
            return this.upperBandDisabled;
        }

        /* JADX INFO: renamed from: component13, reason: from getter */
        public final String getUpperBandLineColor() {
            return this.upperBandLineColor;
        }

        /* JADX INFO: renamed from: component14, reason: from getter */
        public final Integer getUpperBandLineWidth() {
            return this.upperBandLineWidth;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final Boolean getBandAreaDisabled() {
            return this.bandAreaDisabled;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final Boolean getLowerBandDisabled() {
            return this.lowerBandDisabled;
        }

        /* JADX INFO: renamed from: component4, reason: from getter */
        public final String getLowerBandLineColor() {
            return this.lowerBandLineColor;
        }

        /* JADX INFO: renamed from: component5, reason: from getter */
        public final Integer getLowerBandLineWidth() {
            return this.lowerBandLineWidth;
        }

        /* JADX INFO: renamed from: component6, reason: from getter */
        public final Boolean getMaStochRsiDisabled() {
            return this.maStochRsiDisabled;
        }

        /* JADX INFO: renamed from: component7, reason: from getter */
        public final String getMaStochRsiLineColor() {
            return this.maStochRsiLineColor;
        }

        /* JADX INFO: renamed from: component8, reason: from getter */
        public final Integer getMaStochRsiLineWidth() {
            return this.maStochRsiLineWidth;
        }

        /* JADX INFO: renamed from: component9, reason: from getter */
        public final Boolean getStochRsiDisabled() {
            return this.stochRsiDisabled;
        }

        public final Output copy(String bandAreaBackground, Boolean bandAreaDisabled, Boolean lowerBandDisabled, String lowerBandLineColor, Integer lowerBandLineWidth, Boolean maStochRsiDisabled, String maStochRsiLineColor, Integer maStochRsiLineWidth, Boolean stochRsiDisabled, String stochRsiLineColor, Integer stochRsiLineWidth, Boolean upperBandDisabled, String upperBandLineColor, Integer upperBandLineWidth) {
            return new Output(bandAreaBackground, bandAreaDisabled, lowerBandDisabled, lowerBandLineColor, lowerBandLineWidth, maStochRsiDisabled, maStochRsiLineColor, maStochRsiLineWidth, stochRsiDisabled, stochRsiLineColor, stochRsiLineWidth, upperBandDisabled, upperBandLineColor, upperBandLineWidth);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Output)) {
                return false;
            }
            Output output = (Output) other;
            return AbstractC7609s.f(this.bandAreaBackground, output.bandAreaBackground) && AbstractC7609s.f(this.bandAreaDisabled, output.bandAreaDisabled) && AbstractC7609s.f(this.lowerBandDisabled, output.lowerBandDisabled) && AbstractC7609s.f(this.lowerBandLineColor, output.lowerBandLineColor) && AbstractC7609s.f(this.lowerBandLineWidth, output.lowerBandLineWidth) && AbstractC7609s.f(this.maStochRsiDisabled, output.maStochRsiDisabled) && AbstractC7609s.f(this.maStochRsiLineColor, output.maStochRsiLineColor) && AbstractC7609s.f(this.maStochRsiLineWidth, output.maStochRsiLineWidth) && AbstractC7609s.f(this.stochRsiDisabled, output.stochRsiDisabled) && AbstractC7609s.f(this.stochRsiLineColor, output.stochRsiLineColor) && AbstractC7609s.f(this.stochRsiLineWidth, output.stochRsiLineWidth) && AbstractC7609s.f(this.upperBandDisabled, output.upperBandDisabled) && AbstractC7609s.f(this.upperBandLineColor, output.upperBandLineColor) && AbstractC7609s.f(this.upperBandLineWidth, output.upperBandLineWidth);
        }

        public final String getBandAreaBackground() {
            return this.bandAreaBackground;
        }

        public final Boolean getBandAreaDisabled() {
            return this.bandAreaDisabled;
        }

        public final Boolean getLowerBandDisabled() {
            return this.lowerBandDisabled;
        }

        public final String getLowerBandLineColor() {
            return this.lowerBandLineColor;
        }

        public final Integer getLowerBandLineWidth() {
            return this.lowerBandLineWidth;
        }

        public final Boolean getMaStochRsiDisabled() {
            return this.maStochRsiDisabled;
        }

        public final String getMaStochRsiLineColor() {
            return this.maStochRsiLineColor;
        }

        public final Integer getMaStochRsiLineWidth() {
            return this.maStochRsiLineWidth;
        }

        public final Boolean getStochRsiDisabled() {
            return this.stochRsiDisabled;
        }

        public final String getStochRsiLineColor() {
            return this.stochRsiLineColor;
        }

        public final Integer getStochRsiLineWidth() {
            return this.stochRsiLineWidth;
        }

        public final Boolean getUpperBandDisabled() {
            return this.upperBandDisabled;
        }

        public final String getUpperBandLineColor() {
            return this.upperBandLineColor;
        }

        public final Integer getUpperBandLineWidth() {
            return this.upperBandLineWidth;
        }

        public int hashCode() {
            String str = this.bandAreaBackground;
            int iHashCode = (str == null ? 0 : str.hashCode()) * 31;
            Boolean bool = this.bandAreaDisabled;
            int iHashCode2 = (iHashCode + (bool == null ? 0 : bool.hashCode())) * 31;
            Boolean bool2 = this.lowerBandDisabled;
            int iHashCode3 = (iHashCode2 + (bool2 == null ? 0 : bool2.hashCode())) * 31;
            String str2 = this.lowerBandLineColor;
            int iHashCode4 = (iHashCode3 + (str2 == null ? 0 : str2.hashCode())) * 31;
            Integer num = this.lowerBandLineWidth;
            int iHashCode5 = (iHashCode4 + (num == null ? 0 : num.hashCode())) * 31;
            Boolean bool3 = this.maStochRsiDisabled;
            int iHashCode6 = (iHashCode5 + (bool3 == null ? 0 : bool3.hashCode())) * 31;
            String str3 = this.maStochRsiLineColor;
            int iHashCode7 = (iHashCode6 + (str3 == null ? 0 : str3.hashCode())) * 31;
            Integer num2 = this.maStochRsiLineWidth;
            int iHashCode8 = (iHashCode7 + (num2 == null ? 0 : num2.hashCode())) * 31;
            Boolean bool4 = this.stochRsiDisabled;
            int iHashCode9 = (iHashCode8 + (bool4 == null ? 0 : bool4.hashCode())) * 31;
            String str4 = this.stochRsiLineColor;
            int iHashCode10 = (iHashCode9 + (str4 == null ? 0 : str4.hashCode())) * 31;
            Integer num3 = this.stochRsiLineWidth;
            int iHashCode11 = (iHashCode10 + (num3 == null ? 0 : num3.hashCode())) * 31;
            Boolean bool5 = this.upperBandDisabled;
            int iHashCode12 = (iHashCode11 + (bool5 == null ? 0 : bool5.hashCode())) * 31;
            String str5 = this.upperBandLineColor;
            int iHashCode13 = (iHashCode12 + (str5 == null ? 0 : str5.hashCode())) * 31;
            Integer num4 = this.upperBandLineWidth;
            return iHashCode13 + (num4 != null ? num4.hashCode() : 0);
        }

        public String toString() {
            return "Output(bandAreaBackground=" + this.bandAreaBackground + ", bandAreaDisabled=" + this.bandAreaDisabled + ", lowerBandDisabled=" + this.lowerBandDisabled + ", lowerBandLineColor=" + this.lowerBandLineColor + ", lowerBandLineWidth=" + this.lowerBandLineWidth + ", maStochRsiDisabled=" + this.maStochRsiDisabled + ", maStochRsiLineColor=" + this.maStochRsiLineColor + ", maStochRsiLineWidth=" + this.maStochRsiLineWidth + ", stochRsiDisabled=" + this.stochRsiDisabled + ", stochRsiLineColor=" + this.stochRsiLineColor + ", stochRsiLineWidth=" + this.stochRsiLineWidth + ", upperBandDisabled=" + this.upperBandDisabled + ", upperBandLineColor=" + this.upperBandLineColor + ", upperBandLineWidth=" + this.upperBandLineWidth + ')';
        }
    }

    public StochRSIRemote(Input input, Output output, Output output2, Input input2) {
        this.input = input;
        this.output = output;
        this.app_output = output2;
        this.app_input = input2;
    }

    public static /* synthetic */ StochRSIRemote copy$default(StochRSIRemote stochRSIRemote, Input input, Output output, Output output2, Input input2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            input = stochRSIRemote.input;
        }
        if ((i10 & 2) != 0) {
            output = stochRSIRemote.output;
        }
        if ((i10 & 4) != 0) {
            output2 = stochRSIRemote.app_output;
        }
        if ((i10 & 8) != 0) {
            input2 = stochRSIRemote.app_input;
        }
        return stochRSIRemote.copy(input, output, output2, input2);
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

    public final StochRSIRemote copy(Input input, Output output, Output app_output, Input app_input) {
        return new StochRSIRemote(input, output, app_output, app_input);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof StochRSIRemote)) {
            return false;
        }
        StochRSIRemote stochRSIRemote = (StochRSIRemote) other;
        return AbstractC7609s.f(this.input, stochRSIRemote.input) && AbstractC7609s.f(this.output, stochRSIRemote.output) && AbstractC7609s.f(this.app_output, stochRSIRemote.app_output) && AbstractC7609s.f(this.app_input, stochRSIRemote.app_input);
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
        return "StochRSIRemote(input=" + this.input + ", output=" + this.output + ", app_output=" + this.app_output + ", app_input=" + this.app_input + ')';
    }
}
