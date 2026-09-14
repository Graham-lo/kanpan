package Rj;

import android.animation.TypeEvaluator;

/* JADX INFO: loaded from: classes7.dex */
public final class A0 implements TypeEvaluator {
    @Override // android.animation.TypeEvaluator
    /* JADX INFO: renamed from: a, reason: merged with bridge method [inline-methods] */
    public Qf.p evaluate(float f10, Qf.p pVar, Qf.p pVar2) {
        double dN = p292ng.i.n(((double) f10) + 0.3d, 0.3d, 1.0d);
        return new Qf.p(Double.valueOf(((((Number) pVar2.c()).doubleValue() - ((Number) pVar.c()).doubleValue()) * dN) + ((Number) pVar.c()).doubleValue()), Double.valueOf(((((Number) pVar2.d()).doubleValue() - ((Number) pVar.d()).doubleValue()) * dN) + ((Number) pVar.d()).doubleValue()));
    }
}
