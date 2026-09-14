package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import okhttp3.dnsoverhttps.DnsOverHttps;
import okhttp3.internal.http2.Http2;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000.\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0010\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0003\b\u0087\b\u0018\u00002\u00020\u0001:\u0002\u001c\u001dB/\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\b\u0010\tJ\u000b\u0010\u0010\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u0011\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0012\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0013\u001a\u0004\u0018\u00010\u0003HÆ\u0003J9\u0010\u0014\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\u0015\u001a\u00020\u00162\b\u0010\u0017\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0018\u001a\u00020\u0019HÖ\u0001J\t\u0010\u001a\u001a\u00020\u001bHÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\n\u0010\u000bR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\f\u0010\rR\u0013\u0010\u0006\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\rR\u0013\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u000f\u0010\u000b¨\u0006\u001e"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/IchimokuRemote;", "", "input", "Lsp/aicoin_kline/core/indicator/config/IchimokuRemote$Input;", "output", "Lsp/aicoin_kline/core/indicator/config/IchimokuRemote$Output;", "app_output", "app_input", "<init>", "(Lsp/aicoin_kline/core/indicator/config/IchimokuRemote$Input;Lsp/aicoin_kline/core/indicator/config/IchimokuRemote$Output;Lsp/aicoin_kline/core/indicator/config/IchimokuRemote$Output;Lsp/aicoin_kline/core/indicator/config/IchimokuRemote$Input;)V", "getInput", "()Lsp/aicoin_kline/core/indicator/config/IchimokuRemote$Input;", "getOutput", "()Lsp/aicoin_kline/core/indicator/config/IchimokuRemote$Output;", "getApp_output", "getApp_input", "component1", "component2", "component3", "component4", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Input", "Output", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class IchimokuRemote {
    private final Input app_input;
    private final Output app_output;
    private final Input input;
    private final Output output;

    @Keep
    @Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0002\b\u0013\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0010\u000e\n\u0000\b\u0087\b\u0018\u00002\u00020\u0001B-\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0005\u001a\u0004\u0018\u00010\u0003\u0012\u0006\u0010\u0006\u001a\u00020\u0003¢\u0006\u0004\b\u0007\u0010\bJ\u0010\u0010\u0010\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\nJ\u0010\u0010\u0011\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\nJ\u0010\u0010\u0012\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\nJ\t\u0010\u0013\u001a\u00020\u0003HÆ\u0003J<\u0010\u0014\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0005\u001a\u0004\u0018\u00010\u00032\b\b\u0002\u0010\u0006\u001a\u00020\u0003HÆ\u0001¢\u0006\u0002\u0010\u0015J\u0013\u0010\u0016\u001a\u00020\u00172\b\u0010\u0018\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0019\u001a\u00020\u0003HÖ\u0001J\t\u0010\u001a\u001a\u00020\u001bHÖ\u0001R\u0015\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\u000b\u001a\u0004\b\t\u0010\nR\u0015\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\u000b\u001a\u0004\b\f\u0010\nR\u0015\u0010\u0005\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\u000b\u001a\u0004\b\r\u0010\nR\u0011\u0010\u0006\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\u000f¨\u0006\u001c"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/IchimokuRemote$Input;", "", "conversionCycle", "", "baseCycle", "laggingSpan2Cycle", "displacement", "<init>", "(Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;I)V", "getConversionCycle", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getBaseCycle", "getLaggingSpan2Cycle", "getDisplacement", "()I", "component1", "component2", "component3", "component4", "copy", "(Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;I)Lsp/aicoin_kline/core/indicator/config/IchimokuRemote$Input;", "equals", "", "other", "hashCode", "toString", "", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Input {
        private final Integer baseCycle;
        private final Integer conversionCycle;
        private final int displacement;
        private final Integer laggingSpan2Cycle;

        public Input(Integer num, Integer num2, Integer num3, int i10) {
            this.conversionCycle = num;
            this.baseCycle = num2;
            this.laggingSpan2Cycle = num3;
            this.displacement = i10;
        }

        public static /* synthetic */ Input copy$default(Input input, Integer num, Integer num2, Integer num3, int i10, int i11, Object obj) {
            if ((i11 & 1) != 0) {
                num = input.conversionCycle;
            }
            if ((i11 & 2) != 0) {
                num2 = input.baseCycle;
            }
            if ((i11 & 4) != 0) {
                num3 = input.laggingSpan2Cycle;
            }
            if ((i11 & 8) != 0) {
                i10 = input.displacement;
            }
            return input.copy(num, num2, num3, i10);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Integer getConversionCycle() {
            return this.conversionCycle;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final Integer getBaseCycle() {
            return this.baseCycle;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final Integer getLaggingSpan2Cycle() {
            return this.laggingSpan2Cycle;
        }

        /* JADX INFO: renamed from: component4, reason: from getter */
        public final int getDisplacement() {
            return this.displacement;
        }

        public final Input copy(Integer conversionCycle, Integer baseCycle, Integer laggingSpan2Cycle, int displacement) {
            return new Input(conversionCycle, baseCycle, laggingSpan2Cycle, displacement);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Input)) {
                return false;
            }
            Input input = (Input) other;
            return AbstractC7609s.f(this.conversionCycle, input.conversionCycle) && AbstractC7609s.f(this.baseCycle, input.baseCycle) && AbstractC7609s.f(this.laggingSpan2Cycle, input.laggingSpan2Cycle) && this.displacement == input.displacement;
        }

        public final Integer getBaseCycle() {
            return this.baseCycle;
        }

        public final Integer getConversionCycle() {
            return this.conversionCycle;
        }

        public final int getDisplacement() {
            return this.displacement;
        }

        public final Integer getLaggingSpan2Cycle() {
            return this.laggingSpan2Cycle;
        }

        public int hashCode() {
            Integer num = this.conversionCycle;
            int iHashCode = (num == null ? 0 : num.hashCode()) * 31;
            Integer num2 = this.baseCycle;
            int iHashCode2 = (iHashCode + (num2 == null ? 0 : num2.hashCode())) * 31;
            Integer num3 = this.laggingSpan2Cycle;
            return Integer.hashCode(this.displacement) + ((iHashCode2 + (num3 != null ? num3.hashCode() : 0)) * 31);
        }

        public String toString() {
            return "Input(conversionCycle=" + this.conversionCycle + ", baseCycle=" + this.baseCycle + ", laggingSpan2Cycle=" + this.laggingSpan2Cycle + ", displacement=" + this.displacement + ')';
        }
    }

    @Keep
    @Metadata(d1 = {"\u0000\u001e\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b>\b\u0087\b\u0018\u00002\u00020\u0001BÓ\u0001\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\u000e\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u000f\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0010\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\u0011\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0012\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0013\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\u0014\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\u0015\u001a\u0004\u0018\u00010\u0007¢\u0006\u0004\b\u0016\u0010\u0017J\u0010\u0010.\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0019J\u0010\u0010/\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u001cJ\u000b\u00100\u001a\u0004\u0018\u00010\u0007HÆ\u0003J\u0010\u00101\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0019J\u0010\u00102\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u001cJ\u000b\u00103\u001a\u0004\u0018\u00010\u0007HÆ\u0003J\u0010\u00104\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0019J\u0010\u00105\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u001cJ\u000b\u00106\u001a\u0004\u0018\u00010\u0007HÆ\u0003J\u0010\u00107\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0019J\u0010\u00108\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u001cJ\u000b\u00109\u001a\u0004\u0018\u00010\u0007HÆ\u0003J\u0010\u0010:\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0019J\u0010\u0010;\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u001cJ\u000b\u0010<\u001a\u0004\u0018\u00010\u0007HÆ\u0003J\u000b\u0010=\u001a\u0004\u0018\u00010\u0007HÆ\u0003J\u000b\u0010>\u001a\u0004\u0018\u00010\u0007HÆ\u0003JÚ\u0001\u0010?\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\u000e\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u000f\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0010\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\u0011\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0012\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0013\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\u0014\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\u0015\u001a\u0004\u0018\u00010\u0007HÆ\u0001¢\u0006\u0002\u0010@J\u0013\u0010A\u001a\u00020\u00032\b\u0010B\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010C\u001a\u00020\u0005HÖ\u0001J\t\u0010D\u001a\u00020\u0007HÖ\u0001R\u001a\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u001a\u001a\u0004\b\u0018\u0010\u0019R\u001a\u0010\u0004\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u001d\u001a\u0004\b\u001b\u0010\u001cR\u0018\u0010\u0006\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u001e\u0010\u001fR\u001a\u0010\b\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u001a\u001a\u0004\b \u0010\u0019R\u001a\u0010\t\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u001d\u001a\u0004\b!\u0010\u001cR\u0018\u0010\n\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\"\u0010\u001fR\u001a\u0010\u000b\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u001a\u001a\u0004\b#\u0010\u0019R\u001a\u0010\f\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u001d\u001a\u0004\b$\u0010\u001cR\u0018\u0010\r\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b%\u0010\u001fR\u001a\u0010\u000e\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u001a\u001a\u0004\b&\u0010\u0019R\u001a\u0010\u000f\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u001d\u001a\u0004\b'\u0010\u001cR\u0018\u0010\u0010\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b(\u0010\u001fR\u001a\u0010\u0011\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u001a\u001a\u0004\b)\u0010\u0019R\u001a\u0010\u0012\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u001d\u001a\u0004\b*\u0010\u001cR\u0018\u0010\u0013\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b+\u0010\u001fR\u0018\u0010\u0014\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b,\u0010\u001fR\u0018\u0010\u0015\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b-\u0010\u001f¨\u0006E"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/IchimokuRemote$Output;", "", "conversionDisabled", "", "conversion_lineWidth", "", "conversion_lineColor", "", "baseDisabled", "base_lineWidth", "base_lineColor", "laggingSpanDisabled", "laggingSpan_lineWidth", "laggingSpan_lineColor", "lead1Disabled", "lead1_lineWidth", "lead1_lineColor", "lead2Disabled", "lead2_lineWidth", "lead2_lineColor", "rising_background", "falling_background", "<init>", "(Ljava/lang/Boolean;Ljava/lang/Integer;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/Integer;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/Integer;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/Integer;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/Integer;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V", "getConversionDisabled", "()Ljava/lang/Boolean;", "Ljava/lang/Boolean;", "getConversion_lineWidth", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getConversion_lineColor", "()Ljava/lang/String;", "getBaseDisabled", "getBase_lineWidth", "getBase_lineColor", "getLaggingSpanDisabled", "getLaggingSpan_lineWidth", "getLaggingSpan_lineColor", "getLead1Disabled", "getLead1_lineWidth", "getLead1_lineColor", "getLead2Disabled", "getLead2_lineWidth", "getLead2_lineColor", "getRising_background", "getFalling_background", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "component9", "component10", "component11", "component12", "component13", "component14", "component15", "component16", "component17", "copy", "(Ljava/lang/Boolean;Ljava/lang/Integer;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/Integer;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/Integer;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/Integer;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/Integer;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Lsp/aicoin_kline/core/indicator/config/IchimokuRemote$Output;", "equals", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Output {

        @SerializedName("base_disabled")
        private final Boolean baseDisabled;

        @SerializedName("base_lineColor")
        private final String base_lineColor;

        @SerializedName("base_lineWidth")
        private final Integer base_lineWidth;

        @SerializedName("conversion_disabled")
        private final Boolean conversionDisabled;

        @SerializedName("conversion_lineColor")
        private final String conversion_lineColor;

        @SerializedName("conversion_lineWidth")
        private final Integer conversion_lineWidth;

        @SerializedName("falling_background")
        private final String falling_background;

        @SerializedName("laggingSpan_disabled")
        private final Boolean laggingSpanDisabled;

        @SerializedName("laggingSpan_lineColor")
        private final String laggingSpan_lineColor;

        @SerializedName("laggingSpan_lineWidth")
        private final Integer laggingSpan_lineWidth;

        @SerializedName("lead1_disabled")
        private final Boolean lead1Disabled;

        @SerializedName("lead1_lineColor")
        private final String lead1_lineColor;

        @SerializedName("lead1_lineWidth")
        private final Integer lead1_lineWidth;

        @SerializedName("lead2_disabled")
        private final Boolean lead2Disabled;

        @SerializedName("lead2_lineColor")
        private final String lead2_lineColor;

        @SerializedName("lead2_lineWidth")
        private final Integer lead2_lineWidth;

        @SerializedName("rising_background")
        private final String rising_background;

        public Output() {
            this(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, 131071, null);
        }

        public Output(Boolean bool, Integer num, String str, Boolean bool2, Integer num2, String str2, Boolean bool3, Integer num3, String str3, Boolean bool4, Integer num4, String str4, Boolean bool5, Integer num5, String str5, String str6, String str7) {
            this.conversionDisabled = bool;
            this.conversion_lineWidth = num;
            this.conversion_lineColor = str;
            this.baseDisabled = bool2;
            this.base_lineWidth = num2;
            this.base_lineColor = str2;
            this.laggingSpanDisabled = bool3;
            this.laggingSpan_lineWidth = num3;
            this.laggingSpan_lineColor = str3;
            this.lead1Disabled = bool4;
            this.lead1_lineWidth = num4;
            this.lead1_lineColor = str4;
            this.lead2Disabled = bool5;
            this.lead2_lineWidth = num5;
            this.lead2_lineColor = str5;
            this.rising_background = str6;
            this.falling_background = str7;
        }

        public /* synthetic */ Output(Boolean bool, Integer num, String str, Boolean bool2, Integer num2, String str2, Boolean bool3, Integer num3, String str3, Boolean bool4, Integer num4, String str4, Boolean bool5, Integer num5, String str5, String str6, String str7, int i10, DefaultConstructorMarker defaultConstructorMarker) {
            this((i10 & 1) != 0 ? null : bool, (i10 & 2) != 0 ? null : num, (i10 & 4) != 0 ? null : str, (i10 & 8) != 0 ? null : bool2, (i10 & 16) != 0 ? null : num2, (i10 & 32) != 0 ? null : str2, (i10 & 64) != 0 ? null : bool3, (i10 & 128) != 0 ? null : num3, (i10 & 256) != 0 ? null : str3, (i10 & 512) != 0 ? null : bool4, (i10 & 1024) != 0 ? null : num4, (i10 & 2048) != 0 ? null : str4, (i10 & 4096) != 0 ? null : bool5, (i10 & 8192) != 0 ? null : num5, (i10 & Http2.INITIAL_MAX_FRAME_SIZE) != 0 ? null : str5, (i10 & 32768) != 0 ? null : str6, (i10 & DnsOverHttps.MAX_RESPONSE_SIZE) != 0 ? null : str7);
        }

        public static /* synthetic */ Output copy$default(Output output, Boolean bool, Integer num, String str, Boolean bool2, Integer num2, String str2, Boolean bool3, Integer num3, String str3, Boolean bool4, Integer num4, String str4, Boolean bool5, Integer num5, String str5, String str6, String str7, int i10, Object obj) {
            String str8;
            String str9;
            Boolean bool6 = (i10 & 1) != 0 ? output.conversionDisabled : bool;
            Integer num6 = (i10 & 2) != 0 ? output.conversion_lineWidth : num;
            String str10 = (i10 & 4) != 0 ? output.conversion_lineColor : str;
            Boolean bool7 = (i10 & 8) != 0 ? output.baseDisabled : bool2;
            Integer num7 = (i10 & 16) != 0 ? output.base_lineWidth : num2;
            String str11 = (i10 & 32) != 0 ? output.base_lineColor : str2;
            Boolean bool8 = (i10 & 64) != 0 ? output.laggingSpanDisabled : bool3;
            Integer num8 = (i10 & 128) != 0 ? output.laggingSpan_lineWidth : num3;
            String str12 = (i10 & 256) != 0 ? output.laggingSpan_lineColor : str3;
            Boolean bool9 = (i10 & 512) != 0 ? output.lead1Disabled : bool4;
            Integer num9 = (i10 & 1024) != 0 ? output.lead1_lineWidth : num4;
            String str13 = (i10 & 2048) != 0 ? output.lead1_lineColor : str4;
            Boolean bool10 = (i10 & 4096) != 0 ? output.lead2Disabled : bool5;
            Integer num10 = (i10 & 8192) != 0 ? output.lead2_lineWidth : num5;
            Boolean bool11 = bool6;
            String str14 = (i10 & Http2.INITIAL_MAX_FRAME_SIZE) != 0 ? output.lead2_lineColor : str5;
            String str15 = (i10 & 32768) != 0 ? output.rising_background : str6;
            if ((i10 & DnsOverHttps.MAX_RESPONSE_SIZE) != 0) {
                str9 = str15;
                str8 = output.falling_background;
            } else {
                str8 = str7;
                str9 = str15;
            }
            return output.copy(bool11, num6, str10, bool7, num7, str11, bool8, num8, str12, bool9, num9, str13, bool10, num10, str14, str9, str8);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Boolean getConversionDisabled() {
            return this.conversionDisabled;
        }

        /* JADX INFO: renamed from: component10, reason: from getter */
        public final Boolean getLead1Disabled() {
            return this.lead1Disabled;
        }

        /* JADX INFO: renamed from: component11, reason: from getter */
        public final Integer getLead1_lineWidth() {
            return this.lead1_lineWidth;
        }

        /* JADX INFO: renamed from: component12, reason: from getter */
        public final String getLead1_lineColor() {
            return this.lead1_lineColor;
        }

        /* JADX INFO: renamed from: component13, reason: from getter */
        public final Boolean getLead2Disabled() {
            return this.lead2Disabled;
        }

        /* JADX INFO: renamed from: component14, reason: from getter */
        public final Integer getLead2_lineWidth() {
            return this.lead2_lineWidth;
        }

        /* JADX INFO: renamed from: component15, reason: from getter */
        public final String getLead2_lineColor() {
            return this.lead2_lineColor;
        }

        /* JADX INFO: renamed from: component16, reason: from getter */
        public final String getRising_background() {
            return this.rising_background;
        }

        /* JADX INFO: renamed from: component17, reason: from getter */
        public final String getFalling_background() {
            return this.falling_background;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final Integer getConversion_lineWidth() {
            return this.conversion_lineWidth;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final String getConversion_lineColor() {
            return this.conversion_lineColor;
        }

        /* JADX INFO: renamed from: component4, reason: from getter */
        public final Boolean getBaseDisabled() {
            return this.baseDisabled;
        }

        /* JADX INFO: renamed from: component5, reason: from getter */
        public final Integer getBase_lineWidth() {
            return this.base_lineWidth;
        }

        /* JADX INFO: renamed from: component6, reason: from getter */
        public final String getBase_lineColor() {
            return this.base_lineColor;
        }

        /* JADX INFO: renamed from: component7, reason: from getter */
        public final Boolean getLaggingSpanDisabled() {
            return this.laggingSpanDisabled;
        }

        /* JADX INFO: renamed from: component8, reason: from getter */
        public final Integer getLaggingSpan_lineWidth() {
            return this.laggingSpan_lineWidth;
        }

        /* JADX INFO: renamed from: component9, reason: from getter */
        public final String getLaggingSpan_lineColor() {
            return this.laggingSpan_lineColor;
        }

        public final Output copy(Boolean conversionDisabled, Integer conversion_lineWidth, String conversion_lineColor, Boolean baseDisabled, Integer base_lineWidth, String base_lineColor, Boolean laggingSpanDisabled, Integer laggingSpan_lineWidth, String laggingSpan_lineColor, Boolean lead1Disabled, Integer lead1_lineWidth, String lead1_lineColor, Boolean lead2Disabled, Integer lead2_lineWidth, String lead2_lineColor, String rising_background, String falling_background) {
            return new Output(conversionDisabled, conversion_lineWidth, conversion_lineColor, baseDisabled, base_lineWidth, base_lineColor, laggingSpanDisabled, laggingSpan_lineWidth, laggingSpan_lineColor, lead1Disabled, lead1_lineWidth, lead1_lineColor, lead2Disabled, lead2_lineWidth, lead2_lineColor, rising_background, falling_background);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Output)) {
                return false;
            }
            Output output = (Output) other;
            return AbstractC7609s.f(this.conversionDisabled, output.conversionDisabled) && AbstractC7609s.f(this.conversion_lineWidth, output.conversion_lineWidth) && AbstractC7609s.f(this.conversion_lineColor, output.conversion_lineColor) && AbstractC7609s.f(this.baseDisabled, output.baseDisabled) && AbstractC7609s.f(this.base_lineWidth, output.base_lineWidth) && AbstractC7609s.f(this.base_lineColor, output.base_lineColor) && AbstractC7609s.f(this.laggingSpanDisabled, output.laggingSpanDisabled) && AbstractC7609s.f(this.laggingSpan_lineWidth, output.laggingSpan_lineWidth) && AbstractC7609s.f(this.laggingSpan_lineColor, output.laggingSpan_lineColor) && AbstractC7609s.f(this.lead1Disabled, output.lead1Disabled) && AbstractC7609s.f(this.lead1_lineWidth, output.lead1_lineWidth) && AbstractC7609s.f(this.lead1_lineColor, output.lead1_lineColor) && AbstractC7609s.f(this.lead2Disabled, output.lead2Disabled) && AbstractC7609s.f(this.lead2_lineWidth, output.lead2_lineWidth) && AbstractC7609s.f(this.lead2_lineColor, output.lead2_lineColor) && AbstractC7609s.f(this.rising_background, output.rising_background) && AbstractC7609s.f(this.falling_background, output.falling_background);
        }

        public final Boolean getBaseDisabled() {
            return this.baseDisabled;
        }

        public final String getBase_lineColor() {
            return this.base_lineColor;
        }

        public final Integer getBase_lineWidth() {
            return this.base_lineWidth;
        }

        public final Boolean getConversionDisabled() {
            return this.conversionDisabled;
        }

        public final String getConversion_lineColor() {
            return this.conversion_lineColor;
        }

        public final Integer getConversion_lineWidth() {
            return this.conversion_lineWidth;
        }

        public final String getFalling_background() {
            return this.falling_background;
        }

        public final Boolean getLaggingSpanDisabled() {
            return this.laggingSpanDisabled;
        }

        public final String getLaggingSpan_lineColor() {
            return this.laggingSpan_lineColor;
        }

        public final Integer getLaggingSpan_lineWidth() {
            return this.laggingSpan_lineWidth;
        }

        public final Boolean getLead1Disabled() {
            return this.lead1Disabled;
        }

        public final String getLead1_lineColor() {
            return this.lead1_lineColor;
        }

        public final Integer getLead1_lineWidth() {
            return this.lead1_lineWidth;
        }

        public final Boolean getLead2Disabled() {
            return this.lead2Disabled;
        }

        public final String getLead2_lineColor() {
            return this.lead2_lineColor;
        }

        public final Integer getLead2_lineWidth() {
            return this.lead2_lineWidth;
        }

        public final String getRising_background() {
            return this.rising_background;
        }

        public int hashCode() {
            Boolean bool = this.conversionDisabled;
            int iHashCode = (bool == null ? 0 : bool.hashCode()) * 31;
            Integer num = this.conversion_lineWidth;
            int iHashCode2 = (iHashCode + (num == null ? 0 : num.hashCode())) * 31;
            String str = this.conversion_lineColor;
            int iHashCode3 = (iHashCode2 + (str == null ? 0 : str.hashCode())) * 31;
            Boolean bool2 = this.baseDisabled;
            int iHashCode4 = (iHashCode3 + (bool2 == null ? 0 : bool2.hashCode())) * 31;
            Integer num2 = this.base_lineWidth;
            int iHashCode5 = (iHashCode4 + (num2 == null ? 0 : num2.hashCode())) * 31;
            String str2 = this.base_lineColor;
            int iHashCode6 = (iHashCode5 + (str2 == null ? 0 : str2.hashCode())) * 31;
            Boolean bool3 = this.laggingSpanDisabled;
            int iHashCode7 = (iHashCode6 + (bool3 == null ? 0 : bool3.hashCode())) * 31;
            Integer num3 = this.laggingSpan_lineWidth;
            int iHashCode8 = (iHashCode7 + (num3 == null ? 0 : num3.hashCode())) * 31;
            String str3 = this.laggingSpan_lineColor;
            int iHashCode9 = (iHashCode8 + (str3 == null ? 0 : str3.hashCode())) * 31;
            Boolean bool4 = this.lead1Disabled;
            int iHashCode10 = (iHashCode9 + (bool4 == null ? 0 : bool4.hashCode())) * 31;
            Integer num4 = this.lead1_lineWidth;
            int iHashCode11 = (iHashCode10 + (num4 == null ? 0 : num4.hashCode())) * 31;
            String str4 = this.lead1_lineColor;
            int iHashCode12 = (iHashCode11 + (str4 == null ? 0 : str4.hashCode())) * 31;
            Boolean bool5 = this.lead2Disabled;
            int iHashCode13 = (iHashCode12 + (bool5 == null ? 0 : bool5.hashCode())) * 31;
            Integer num5 = this.lead2_lineWidth;
            int iHashCode14 = (iHashCode13 + (num5 == null ? 0 : num5.hashCode())) * 31;
            String str5 = this.lead2_lineColor;
            int iHashCode15 = (iHashCode14 + (str5 == null ? 0 : str5.hashCode())) * 31;
            String str6 = this.rising_background;
            int iHashCode16 = (iHashCode15 + (str6 == null ? 0 : str6.hashCode())) * 31;
            String str7 = this.falling_background;
            return iHashCode16 + (str7 != null ? str7.hashCode() : 0);
        }

        public String toString() {
            return "Output(conversionDisabled=" + this.conversionDisabled + ", conversion_lineWidth=" + this.conversion_lineWidth + ", conversion_lineColor=" + this.conversion_lineColor + ", baseDisabled=" + this.baseDisabled + ", base_lineWidth=" + this.base_lineWidth + ", base_lineColor=" + this.base_lineColor + ", laggingSpanDisabled=" + this.laggingSpanDisabled + ", laggingSpan_lineWidth=" + this.laggingSpan_lineWidth + ", laggingSpan_lineColor=" + this.laggingSpan_lineColor + ", lead1Disabled=" + this.lead1Disabled + ", lead1_lineWidth=" + this.lead1_lineWidth + ", lead1_lineColor=" + this.lead1_lineColor + ", lead2Disabled=" + this.lead2Disabled + ", lead2_lineWidth=" + this.lead2_lineWidth + ", lead2_lineColor=" + this.lead2_lineColor + ", rising_background=" + this.rising_background + ", falling_background=" + this.falling_background + ')';
        }
    }

    public IchimokuRemote(Input input, Output output, Output output2, Input input2) {
        this.input = input;
        this.output = output;
        this.app_output = output2;
        this.app_input = input2;
    }

    public static /* synthetic */ IchimokuRemote copy$default(IchimokuRemote ichimokuRemote, Input input, Output output, Output output2, Input input2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            input = ichimokuRemote.input;
        }
        if ((i10 & 2) != 0) {
            output = ichimokuRemote.output;
        }
        if ((i10 & 4) != 0) {
            output2 = ichimokuRemote.app_output;
        }
        if ((i10 & 8) != 0) {
            input2 = ichimokuRemote.app_input;
        }
        return ichimokuRemote.copy(input, output, output2, input2);
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

    public final IchimokuRemote copy(Input input, Output output, Output app_output, Input app_input) {
        return new IchimokuRemote(input, output, app_output, app_input);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof IchimokuRemote)) {
            return false;
        }
        IchimokuRemote ichimokuRemote = (IchimokuRemote) other;
        return AbstractC7609s.f(this.input, ichimokuRemote.input) && AbstractC7609s.f(this.output, ichimokuRemote.output) && AbstractC7609s.f(this.app_output, ichimokuRemote.app_output) && AbstractC7609s.f(this.app_input, ichimokuRemote.app_input);
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
        return "IchimokuRemote(input=" + this.input + ", output=" + this.output + ", app_output=" + this.app_output + ", app_input=" + this.app_input + ')';
    }
}
